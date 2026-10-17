//! Actual mixed Rust/C leaf conformance only, not a Wasmtime artifact.
#[path = "../owned_handler_thread.rs"]
mod original_thread;
#[path = "../owned_heap.rs"]
mod owned_heap;
#[path = "../owned_abi.rs"]
mod owned_abi;
#[global_allocator]
static ALLOCATOR: owned_heap::OwnedAllocator = owned_heap::OwnedAllocator;

use core::ffi::{c_int, c_void};
use core::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use original_thread::{OwnedHandlerThread, Phase, Stopped};

unsafe extern "C" {
    fn actql_native_owned_current() -> *mut c_void;
    fn actql_native_owned_enter(owner: *mut c_void) -> c_int;
    fn actql_native_owned_leave(owner: *mut c_void) -> c_int;
    fn actql_native_owned_try_close(owner: *mut *mut c_void) -> c_int;
}
static CALLBACKS: AtomicUsize = AtomicUsize::new(0);
static DESTRUCTORS: AtomicUsize = AtomicUsize::new(0);
static ENTERED: AtomicBool = AtomicBool::new(false);
static FINISH: AtomicBool = AtomicBool::new(true);
struct Destructor;
impl Drop for Destructor {
    fn drop(&mut self) {
        let original = unsafe { actql_native_owned_current() };
        assert!(!original.is_null());
        let bytes = vec![37u8; 64];
        assert_eq!(bytes[63], 37);
        DESTRUCTORS.fetch_add(1, Ordering::Release);
    }
}
thread_local! { static DESTRUCTOR: Destructor = const { Destructor }; }
unsafe fn worker() {
    assert!(!unsafe { actql_native_owned_current() }.is_null());
    DESTRUCTOR.with(|_| {});
    let bytes = vec![19u8; 64];
    assert_eq!(bytes.len(), 64);
    CALLBACKS.fetch_add(1, Ordering::Release);
    ENTERED.store(true, Ordering::Release);
    while !FINISH.load(Ordering::Acquire) { std::hint::spin_loop(); }
}
unsafe fn panics() { panic!("original scoped handler panic"); }

#[unsafe(no_mangle)]
pub extern "C" fn actql_test_original_provider_current_address() -> *const c_void {
    actql_native_owned_current as *const c_void
}

#[unsafe(no_mangle)]
pub extern "C" fn actql_test_original_thread_case(index: c_int) -> c_int {
    let owner = unsafe { actql_native_owned_current() };
    assert!(!owner.is_null());
    CALLBACKS.store(0, Ordering::Release);
    DESTRUCTORS.store(0, Ordering::Release);
    ENTERED.store(false, Ordering::Release);
    FINISH.store(index != 3, Ordering::Release);
    let mut original = OwnedHandlerThread::prepare(if index == 1 { panics } else { worker }).unwrap();
    if index == 2 {
        assert_eq!(unsafe { actql_native_owned_leave(owner) }, 0);
        let error = original.start().unwrap_err();
        assert_eq!(error.phase, Phase::Current);
        assert!(!original.ready_in_original_scope());
        assert_eq!(unsafe { actql_native_owned_enter(owner) }, 0);
        assert!(matches!(original.join_after_stop().unwrap(), Stopped::NeverStarted));
        assert_eq!(CALLBACKS.load(Ordering::Acquire), 0);
        return 0;
    }
    original.start().unwrap();
    assert!(original.ready_in_original_scope());
    if index == 3 {
        while !ENTERED.load(Ordering::Acquire) { std::hint::spin_loop(); }
        assert_eq!(unsafe { actql_native_owned_leave(owner) }, 0);
        let mut original_slot = owner;
        assert_eq!(unsafe { actql_native_owned_try_close(&mut original_slot) }, -3);
        assert_eq!(original_slot, owner);
        assert_eq!(unsafe { actql_native_owned_enter(owner) }, 0);
        FINISH.store(true, Ordering::Release);
    }
    let Stopped::Returned(result) = original.join_after_stop().unwrap() else { panic!("missing callback result"); };
    if index == 1 { assert!(result.is_err()); } else {
        assert!(result.is_ok());
        assert_eq!(CALLBACKS.load(Ordering::Acquire), 1);
        assert_eq!(DESTRUCTORS.load(Ordering::Acquire), 1);
    }
    drop(result);
    assert!(!original.ready_in_original_scope());
    assert_eq!(original.join_after_stop().unwrap_err().phase, Phase::Join);
    assert_eq!(unsafe { actql_native_owned_current() }, owner);
    0
}
