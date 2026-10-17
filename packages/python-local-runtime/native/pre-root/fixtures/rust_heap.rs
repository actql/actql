//! Direct calls into the product OwnedAllocator, linked to the actual provider.
//! The harness's own std allocations do not install the product GlobalAlloc.
use std::alloc::{GlobalAlloc, Layout};
use std::ffi::c_void;
use std::ptr;
#[path = "../owned_heap.rs"]
mod heap;
unsafe extern "C" {
    fn actql_native_owned_acquire(bytes: usize, generation: u64, recipe: *const u8, out: *mut *mut c_void) -> i32;
    fn actql_native_owned_transfer(lease: *mut c_void, generation: u64, recipe: *const u8) -> i32;
    fn actql_native_owned_enter(lease: *mut c_void) -> i32;
    fn actql_native_owned_leave(lease: *mut c_void) -> i32;
    fn actql_native_owned_try_close(lease: *mut *mut c_void) -> i32;
}
macro_rules! check {
    ($count:ident, $condition:expr) => {{ assert!($condition); $count += 1; }};
}
fn main() {
    let mut checks = 0;
    unsafe {
        let recipe = [2u8; 32];
        let mut lease = ptr::null_mut();
        check!(checks, actql_native_owned_acquire(64 * 16384, 1, recipe.as_ptr(), &mut lease) == 0 &&
            actql_native_owned_transfer(lease, 1, recipe.as_ptr()) == 0);
        let allocator = heap::OwnedAllocator;
        let layout = Layout::from_size_align(424, 8).unwrap();
        check!(checks, allocator.alloc(layout).is_null());
        check!(checks, actql_native_owned_enter(lease) == 0);
        let pointer = allocator.alloc_zeroed(layout);
        check!(checks, !pointer.is_null() && (0..424).all(|i| *pointer.add(i) == 0));
        ptr::write_bytes(pointer, 47, 424);
        let grown = allocator.realloc(pointer, layout, 1000);
        check!(checks, !grown.is_null() && (0..424).all(|i| *grown.add(i) == 47));
        check!(checks, allocator.realloc(grown, Layout::from_size_align(1000, 8).unwrap(), 64 * 16384).is_null() &&
            (0..424).all(|i| *grown.add(i) == 47));
        let shrunk = allocator.realloc(grown, Layout::from_size_align(1000, 8).unwrap(), 24);
        check!(checks, !shrunk.is_null() && (0..24).all(|i| *shrunk.add(i) == 47));
        let aligned_layout = Layout::from_size_align(31, 32768).unwrap();
        let aligned = allocator.alloc_zeroed(aligned_layout);
        check!(checks, !aligned.is_null() && aligned as usize % 32768 == 0);
        let zero = Layout::from_size_align(0, 8).unwrap();
        let zero_pointer = allocator.alloc(zero);
        check!(checks, !zero_pointer.is_null());
        // Original allocation may outlive its call scope; release uses its own
        // header/token/provider, never the now-unbound current lease.
        check!(checks, actql_native_owned_leave(lease) == 0);
        allocator.dealloc(shrunk, Layout::from_size_align(24, 8).unwrap());
        allocator.dealloc(aligned, aligned_layout);
        allocator.dealloc(zero_pointer, zero);
        check!(checks, actql_native_owned_try_close(&mut lease) == 0 && lease.is_null());
        check!(checks, actql_native_owned_try_close(&mut lease) == 0 && lease.is_null());
        assert_eq!(checks, 12);
        println!("{{\"rust_global_alloc_checks\":12,\"passed\":12,\"wasmtime\":0,\"normal_profile\":null}}");
    }
}
