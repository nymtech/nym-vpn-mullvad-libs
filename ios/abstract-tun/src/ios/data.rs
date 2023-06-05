type DataAppendCall =
    extern "C" fn(swift_data_ptr: *mut SwiftData, bytes_ptr: *const u8, bytes_size: usize);

type DataDropCall = extern "C" fn(swift_data_ptr: *mut SwiftData);

#[repr(C)]
pub struct BorrowedSwiftData {
    borrowed_data_ptr: *mut u8,
    size: usize,
}

#[repr(C)]
pub struct SwiftData {
    swift_data_ptr: *mut libc::c_void,
    bytes_ptr: *mut u8,
    size: usize,
}

extern "C" {
    fn run_swift_from_rust() -> u64;
    fn drop_swift_data(swift_data_ptr: *mut SwiftData);
}

impl SwiftData {
    pub unsafe fn from_raw(
        swift_data_ptr: *mut libc::c_void,
        bytes_ptr: *mut u8,
        size: usize,
    ) -> Self {
        Self {
            swift_data_ptr,
            bytes_ptr,
            size,
            // drop_callback,
            // append_callback,
        }
    }

    pub fn append(&mut self, bytes: &[u8]) {
        // (self.append_callback)(self as *mut _, bytes.as_ptr(), bytes.len())
    }

    pub fn forget(self) {
        std::mem::forget(self)
    }
}

impl AsMut<[u8]> for SwiftData {
    fn as_mut(&mut self) -> &mut [u8] {
        // SAFETY: `self.bytes_ptr` must be valid for `self.size` bytes
        unsafe { std::slice::from_raw_parts_mut(self.bytes_ptr, self.size) }
    }
}

impl Drop for SwiftData {
    fn drop(&mut self) {
        // (self.drop_callback)(self as *mut _)
    }
}

type CreateDataCallback = extern "C" fn(size: usize) -> SwiftData;

#[repr(C)]
pub struct SwiftDataFactory {
    create_callback: CreateDataCallback,
}

impl SwiftDataFactory {
    pub fn create(&self, size: usize) -> SwiftData {
        (self.create_callback)(size)
    }
}

type DataArrayAppend = extern "C" fn(arry_ptr: *mut SwiftDataArray, data: SwiftData);
type DataArrayIterate = extern "C" fn(arry_ptr: *mut SwiftDataArray);

type DataIteratorFunc = extern "C" fn(context: ArrayIteratorContext, data: SwiftData);
type DataArrayDrop = extern "C" fn(array_ptr: *mut SwiftDataArray);

/// Wrapper arround Swift's `[Data]`
#[repr(C)]
pub struct SwiftDataArray {
    array_ptr: *mut libc::c_void,
    append_callback: DataArrayAppend,
    iterate_callback: DataArrayIterate,
    drop_callback: DataArrayDrop,
}

impl SwiftDataArray {
    pub fn append(&mut self, data: SwiftData) {
        (self.append_callback)(self as *mut _, data)
    }
}


impl Drop for SwiftDataArray {
    fn drop(&mut self) {
        (self.drop_callback)(self as *mut _)
    }
}

#[repr(C)]
struct ArrayIteratorContext {}
