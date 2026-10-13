//! Proposed private allocator exports in the final C API cdylib.
//! No allocation or Owner decisions are made by these forwarding functions.

use core::ffi::{c_int, c_void};

unsafe extern "C" {
    fn actql_native_owned_acquire(capacity: usize, generation: u64,
                                  recipe: *const u8, out: *mut *mut c_void) -> c_int;
    fn actql_native_owned_transfer(lease: *mut c_void, generation: u64,
                                   recipe: *const u8) -> c_int;
    fn actql_native_owned_enter(lease: *mut c_void) -> c_int;
    fn actql_native_owned_leave(lease: *mut c_void) -> c_int;
    fn actql_native_owned_current() -> *mut c_void;
    fn actql_native_owned_allocate(lease: *mut c_void, bytes: usize,
                                   alignment: usize, out: *mut *mut c_void) -> c_int;
    fn actql_native_owned_protect(lease: *mut c_void, allocation: *mut c_void,
                                  offset: usize, length: usize, protection: c_int) -> c_int;
    fn actql_native_owned_retire(lease: *mut c_void, allocation: *mut c_void) -> c_int;
    fn actql_native_owned_try_close(lease: *mut *mut c_void) -> c_int;
}

macro_rules! forward {
    ($name:ident, $native:ident, ($($argument:ident: $kind:ty),*), $output:ty) => {
        // SAFETY: The private caller supplies the original owning native handle,
        // valid pointer slots and exact recipe bytes. This forwards their lifetime
        // contract unchanged. It is not an interface for arbitrary user pointers.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name($($argument: $kind),*) -> $output {
            unsafe { $native($($argument),*) }
        }
    };
}

forward!(actql_owned_acquire, actql_native_owned_acquire,
         (capacity: usize, generation: u64, recipe: *const u8, out: *mut *mut c_void), c_int);
forward!(actql_owned_transfer, actql_native_owned_transfer,
         (lease: *mut c_void, generation: u64, recipe: *const u8), c_int);
forward!(actql_owned_enter, actql_native_owned_enter, (lease: *mut c_void), c_int);
forward!(actql_owned_leave, actql_native_owned_leave, (lease: *mut c_void), c_int);
forward!(actql_owned_current, actql_native_owned_current, (), *mut c_void);
forward!(actql_owned_allocate, actql_native_owned_allocate,
         (lease: *mut c_void, bytes: usize, alignment: usize, out: *mut *mut c_void), c_int);
forward!(actql_owned_protect, actql_native_owned_protect,
         (lease: *mut c_void, allocation: *mut c_void, offset: usize, length: usize,
          protection: c_int), c_int);
forward!(actql_owned_retire, actql_native_owned_retire,
         (lease: *mut c_void, allocation: *mut c_void), c_int);
forward!(actql_owned_try_close, actql_native_owned_try_close,
         (lease: *mut *mut c_void), c_int);
