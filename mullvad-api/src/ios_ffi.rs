use std::{net::SocketAddr, sync::Arc};

use crate::{
    rest::{self, MullvadRestHandle},
    AccountsProxy, DevicesProxy,
};

#[repr(i32)]
enum FfiError {
    NoError = 0,
    StringParsing = -1,
    SocketAddressParsing = -2,
    AsyncRuntimeInitialization = -3,
    BadResponse = -4,
}

/// IosMullvadApiClient is an FFI interface to our `mullvad-api`. It is a thread-safe to accessing
/// our API.
#[repr(C)]
struct IosMullvadApiClient {
    ptr: *const IosApiContextInner,
}

impl IosMullvadApiClient {
    fn new(context: IosApiContextInner) -> Self {
        let sync_context = Arc::new(context);
        let ptr = Arc::into_raw(sync_context);
        Self { ptr }
    }

    unsafe fn from_raw(self) -> Arc<IosApiContextInner> {
        unsafe {
            Arc::increment_strong_count(self.ptr);
        }

        Arc::from_raw(self.ptr)
    }
}

struct IosApiClientContext {
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

    fn tokio_handle(self: &Arc<Self>) -> tokio::runtime::Handle {
        self.tokio_runtime.handle().clone()
    }
}

/// Paramters:
/// `api_address`: pointer to UTF-8 string containing a socket address representation
/// ("143.32.4.32:9090"), the port is mandatory.
///
/// `api_address_len`: size of the API address string
#[no_mangle]
extern "C" fn mullvad_api_initialize_api_runtime(
    context_ptr: *mut IosMullvadApiClient,
    api_address_ptr: *const u8,
    api_address_len: usize,
    hostname: *const u8,
    hostname_len: usize,
) -> FfiError {
    let Some(addr_str) = (unsafe { string_from_raw_ptr(api_address_ptr, api_address_len) }) else {
        return FfiError::StringParsing;
    };
    let Some(api_hostname) = (unsafe { string_from_raw_ptr(hostname, hostname_len) }) else {
        return FfiError::StringParsing;
    };

    let Ok(api_address): Result<SocketAddr, _> = addr_str.parse() else {
        return FfiError::SocketAddressParsing;
    };

    let mut runtime_builder = tokio::runtime::Builder::new_multi_thread();

    runtime_builder.worker_threads(2).enable_all();
    let Ok(tokio_runtime) = runtime_builder.build() else {
        return FfiError::AsyncRuntimeInitialization;
    };

    let api_runtime = crate::Runtime::with_static_addr(tokio_runtime.handle().clone(), api_address);

    let ios_context = IosApiContextInner {
        tokio_runtime,
        api_runtime,
        api_hostname,
    };

    let context = IosMullvadApiClient::new(ios_context);

    unsafe {
        std::ptr::write(context_ptr, context);
    }

    FfiError::NoError
}

#[no_mangle]
extern "C" fn mullvad_api_remove_all_devices_from_account(
    context: IosMullvadApiClient,
    account_str_ptr: *const u8,
    account_str_len: usize,
) -> FfiError {
    let ctx = unsafe { context.from_raw() };
    let Some(account) = (unsafe { string_from_raw_ptr(account_str_ptr, account_str_len) }) else {
        return FfiError::StringParsing;
    };

    let runtime = ctx.tokio_handle();
    let device_proxy = ctx.devices_proxy();
    let result = runtime.block_on(async move {
        let devices = device_proxy.list(account.clone()).await?;
        for device in devices {
            device_proxy.remove(account.clone(), device.id).await?;
        }
        Result::<_, rest::Error>::Ok(())
    });

    match result {
        Ok(()) => FfiError::NoError,
        Err(_err) => FfiError::BadResponse,
    }
}

#[no_mangle]
extern "C" fn mullvad_api_get_expiry_for_account(
    context: IosMullvadApiClient,
    account_str_ptr: *const u8,
    account_str_len: usize,
    expiry_timestamp: *mut libc::timespec,
) -> FfiError {
    let Some(account) = (unsafe { string_from_raw_ptr(account_str_ptr, account_str_len) }) else {
        return FfiError::StringParsing;
    };

    let ctx = unsafe { context.from_raw() };
    let runtime = ctx.tokio_handle();

    let account_proxy = ctx.accounts_proxy();
    let result: Result<_, rest::Error> = runtime.block_on(async move {
        let expiry = account_proxy.get_data(account).await?.expiry;
        let seconds = expiry.timestamp();
        let nanos = expiry.timestamp_nanos();

        Ok(libc::timespec {
            tv_sec: seconds,
            tv_nsec: nanos,
        })
    });

    match result {
        Ok(expiry) => {
            // SAFETY: It is assumed that expiry_timestamp is a valid pointer to a `libc::timespec`
            unsafe {
                std::ptr::write(expiry_timestamp, expiry);
            }
            FfiError::NoError
        }
        Err(_err) => FfiError::BadResponse,
    }
}

/// Args:
/// context: `IosApiContext`
/// public_key: a pointer to a valid 32 byte array representing a WireGuard public key
#[no_mangle]
extern "C" fn mullvad_api_add_device_for_account(
    context: IosMullvadApiClient,
    account_str_ptr: *const u8,
    account_str_len: usize,
    public_key_ptr: *const u8,
) -> FfiError {
    let Some(account) = (unsafe { string_from_raw_ptr(account_str_ptr, account_str_len) }) else {
        return FfiError::StringParsing;
    };
    let public_key_bytes: [u8; 32] = unsafe { std::ptr::read(public_key_ptr as *const _) };
    let public_key = public_key_bytes.into();

    let ctx = unsafe { context.from_raw() };
    let runtime = ctx.tokio_handle();

    let devices_proxy = ctx.devices_proxy();

    let result: Result<_, rest::Error> = runtime.block_on(async move {
        let (new_device, _) = devices_proxy.create(account, public_key).await?;
        Ok(new_device)
    });

    match result {
        Ok(_result) => FfiError::NoError,
        Err(_err) => FfiError::BadResponse,
    }
}

#[no_mangle]
extern "C" fn mullvad_api_runtime_drop(context: IosMullvadApiClient) {
    unsafe { Arc::decrement_strong_count(context.ptr) }
}

/// The return value is only valid for the lifetime of the `ptr` that's passed in
///
/// SAFETY: `ptr` must be valid for `size` bytes
unsafe fn string_from_raw_ptr(ptr: *const u8, size: usize) -> Option<String> {
    let slice = unsafe { std::slice::from_raw_parts(ptr, size) };

    String::from_utf8(slice.to_vec()).ok()
}
