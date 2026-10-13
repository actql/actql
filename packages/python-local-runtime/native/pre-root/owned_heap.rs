//! Uncompiled allocator candidate for the selected C API artifact only.
//!
//! No system allocation fallback is permitted. This routes Rust allocation
//! storage, not Core capacity decisions. Infallible Rust allocation exhaustion
//! is still an adoption blocker: returning null is not a typed Owner refusal.

use core::alloc::{GlobalAlloc, Layout};
use core::ffi::c_void;
use core::mem::{align_of, size_of};
use core::ptr;

unsafe extern "C" {
    fn actql_owned_current() -> *mut c_void;
    fn actql_owned_allocate(lease: *mut c_void, bytes: usize, alignment: usize,
                            out: *mut *mut c_void) -> i32;
    fn actql_owned_retire(lease: *mut c_void, allocation: *mut c_void) -> i32;
}

#[repr(C)]
#[derive(Clone, Copy)]
struct AllocationHeader {
    lease: *mut c_void,
    extent: *mut c_void,
    size: usize,
    alignment: usize,
}

pub(crate) struct OwnedAllocator;

impl OwnedAllocator {
    unsafe fn allocate(lease: *mut c_void, layout: Layout) -> *mut u8 {
        if lease.is_null() {
            return ptr::null_mut();
        }
        let alignment = layout.align().max(align_of::<AllocationHeader>());
        let Some(prefix) = size_of::<AllocationHeader>()
            .checked_add(alignment - 1)
            .map(|bytes| bytes & !(alignment - 1)) else {
                return ptr::null_mut();
            };
        let Some(bytes) = prefix.checked_add(layout.size().max(1)) else {
            return ptr::null_mut();
        };
        if bytes > isize::MAX as usize {
            return ptr::null_mut();
        }
        let mut extent = ptr::null_mut();
        if unsafe { actql_owned_allocate(lease, bytes, alignment, &mut extent) } != 0 {
            return ptr::null_mut();
        }
        // The native extent starts at the requested alignment and contains
        // the header/padding and payload. Both remain in the original holding.
        let output = unsafe { extent.cast::<u8>().add(prefix) };
        let header = unsafe { output.sub(size_of::<AllocationHeader>()) }
            .cast::<AllocationHeader>();
        unsafe {
            header.write(AllocationHeader {
                lease, extent, size: layout.size(), alignment: layout.align(),
            });
        }
        output
    }

    unsafe fn header(pointer: *mut u8) -> AllocationHeader {
        unsafe {
            pointer.sub(size_of::<AllocationHeader>())
                .cast::<AllocationHeader>().read()
        }
    }
}

// SAFETY: Allocation storage comes from the original synchronized native
// holding, with checked size/alignment and disjoint live extents. A header
// retains the original lease and extent even after its native call scope exits.
// Callers must obey GlobalAlloc's pointer/layout contract. The original LocalCore
// cannot release the lease while a retained extent or native handle is live.
unsafe impl GlobalAlloc for OwnedAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        unsafe { Self::allocate(actql_owned_current(), layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        // Native allocation zeroes the complete newly accessible extent.
        unsafe { self.alloc(layout) }
    }

    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        let header = unsafe { Self::header(pointer) };
        if header.size != layout.size() || header.alignment != layout.align() {
            // Do not release a foreign/mismatched extent. This cannot establish
            // cleanup success; the original holding remains busy.
            return;
        }
        // Physical failure stays as a retired extent in the same lease, and
        // final native lease cleanup retries it. Never free through System.
        let _ = unsafe { actql_owned_retire(header.lease, header.extent) };
    }

    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        let header = unsafe { Self::header(pointer) };
        if header.size != layout.size() || header.alignment != layout.align() ||
            header.lease != unsafe { actql_owned_current() } {
            return ptr::null_mut();
        }
        let Ok(next_layout) = Layout::from_size_align(size, layout.align()) else {
            return ptr::null_mut();
        };
        let next = unsafe { Self::allocate(header.lease, next_layout) };
        if next.is_null() {
            // The original allocation remains live if the new extent fails.
            return next;
        }
        unsafe { ptr::copy_nonoverlapping(pointer, next, layout.size().min(size)); }
        unsafe { self.dealloc(pointer, layout); }
        next
    }
}
