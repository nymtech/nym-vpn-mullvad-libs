use std::{net::SocketAddr, sync::Arc};

use crate::{rest::MullvadRestHandle, AccountsProxy, DevicesProxy};

#[repr(C)]
struct IosApiContext {
    ptr: *const IosApiContextInner,
}

impl IosApiContext {
    fn new(context: IosApiContextInner) -> Self {
        let sync_context = Arc::new(context);
        let ptr = Arc::into_raw(sync_context);
        unsafe {
            Arc::increment_strong_count(ptr);
        }
        Self { ptr }
    }

    unsafe fn from_raw(self) -> Arc<IosApiContextInner> {
        Arc::from_raw(self.ptr)
    }
}

struct IosApiContextInner {
    tokio_runtime: tokio::runtime::Runtime,
    api_runtime: crate::Runtime,
    api_hostname: String,
}

impl IosApiContextInner {
    fn rest_handle(self: Arc<Self>) -> MullvadRestHandle {
        self.tokio_runtime.block_on(
            self.api_runtime
                .static_mullvad_rest_handle(self.api_hostname.clone()),
        )
    }

    fn devices_proxy(self: Arc<Self>) -> DevicesProxy {
        crate::DevicesProxy::new(self.rest_handle())
    }

    fn accounts_proxy(self: Arc<Self>) -> AccountsProxy {
        crate::AccountsProxy::new(self.rest_handle())
    }

    fn tokio_handle(self: Arc<Self>) -> tokio::runtime::Handle {
        self.tokio_runtime.handle().clone()
    }
}

#[repr(C)]
struct DeviceResponse {
    size: usize,
    devices: [DeviceUuid; 5],
}

#[repr(C)]
struct DeviceUuid {
    ptr: *const u8,
    size: usize,
}

#[repr(C)]
struct IosAccountExpiry {}

/// Paramters:
/// `api_address`: pointer to UTF-8 string containing a socket address representation
/// ("143.32.4.32:9090"), the port is mandatory.
///
/// `api_address_len`: size of the API address string
#[no_mangle]
extern "C" fn mullvad_api_initialize_api_runtime(
    context_ptr: *mut IosApiContext,
    api_address_ptr: *const u8,
    api_address_len: usize,
    hostname: *const u8,
    hostname_len: usize,
) -> i32 {
    let Some(addr_str) = (unsafe { string_from_raw_ptr(api_address_ptr, api_address_len) }) else {
        return -1;
    };
    let Some(api_hostname) = (unsafe { string_from_raw_ptr(hostname, hostname_len) }) else {
        return -1;
    };

    let Ok(api_address): Result<SocketAddr, _> = addr_str.parse() else {
        return -2;
    };

    let mut runtime_builder = tokio::runtime::Builder::new_multi_thread();

    runtime_builder.worker_threads(2).enable_all();
    let Ok(tokio_runtime) = runtime_builder.build() else {
        return -3;
    };

    let api_runtime = crate::Runtime::with_static_addr(tokio_runtime.handle().clone(), api_address);

    let ios_context = IosApiContextInner {
        tokio_runtime,
        api_runtime,
        api_hostname,
    };

    let context = IosApiContext::new(ios_context);

    unsafe {
        std::ptr::write(context_ptr, context);
    }

    0
}

#[no_mangle]
extern "C" fn mullvad_api_get_devices_for_account(
    context: IosApiContext,
    account_str: *const u8,
    account_str_len: usize,
    device_response: &mut DeviceResponse,
) -> i32 {
    let ctx = unsafe { context.from_raw() };
    let Some(account) = (unsafe { string_from_raw_ptr(account_str, account_str_len) }) else {
        return -1;
    };

    let runtime = ctx.tokio_runtime();
    let devices = ctx.devices_proxy();
    drop(ctx);

    let Ok(devices) = runtime.block_on(devices.list(account)) else {
        return -4;
    };

    0
}

#[no_mangle]
extern "C" fn mullvad_api_get_expiry_for_account(
    context: IosApiContext,
    account_str: *const u8,
    length: usize,
    device_response: &mut IosAccountExpiry,
) -> i32 {
    -1
}

#[no_mangle]
extern "C" fn mullvad_api_remove_devices_from_account(
    context: IosApiContext,
    account_str: *const u8,
    account_str_length: usize,
    uuid_str: *const u8,
    uuid_str_length: usize,
) -> i32 {
    -1
}

#[no_mangle]
extern "C" fn mullvad_api_add_device_for_account(
    context: IosApiContext,
    account_str: *const u8,
    account_str_length: usize,
    uuid_str: *const u8,
    uuid_str_length: usize,
) -> i32 {
    -1
}

#[no_mangle]
extern "C" fn mullvad_api_runtime_drop(context: IosApiContext) {
    unsafe { Arc::decrement_strong_count(context.ptr) }
}

/// The return value is only valid for the lifetime of the `ptr` that's passed in
///
/// SAFETY: `ptr` must be valid for `size` bytes
unsafe fn string_from_raw_ptr(ptr: *const u8, size: usize) -> Option<String> {
    let slice = unsafe { std::slice::from_raw_parts(ptr, size) };

    String::from_utf8(slice.to_vec()).ok()
}

extern "C" fn mullvad_api_deinit_response(device_list: DeviceResponse) {
    for i in 0..std::cmp::max(device_list.size, 5) {
        let device_uuid = device_list.device[i];
        let _ = unsafe { String::from_raw_parts(device_uuid.ptr, device_uuid.size) };
    }
}
