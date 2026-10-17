//! Selected Darwin Mach-handler attachment to the SAME native provider.
//!
//! This is a physical lifetime wrapper, not a thread registry, funding issuer or
//! replacement Backend. The existing process/runtime handler owns it before
//! start and through original port-stop, join and allocation retirement.

use core::cell::UnsafeCell;
use core::ffi::{c_int, c_void};
use core::mem::{MaybeUninit, align_of, size_of};
use core::ptr;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::thread;

#[link(name = "actql_native_control", kind = "dylib")]
unsafe extern "C" {
    fn actql_native_owned_current() -> *mut c_void;
    fn actql_native_owned_allocate(owner: *mut c_void, bytes: usize, alignment: usize,
                                   output: *mut *mut c_void) -> c_int;
    fn actql_native_owned_retire(owner: *mut c_void, allocation: *mut c_void) -> c_int;
    fn actql_native_owned_thread_control_bytes() -> usize;
    fn actql_native_owned_thread_control_alignment() -> usize;
    fn actql_native_owned_thread_start_configured(owner: *mut c_void, control: *mut c_void,
        bytes: usize, attributes: *const c_void,
        entry: unsafe extern "C" fn(*mut c_void), argument: *mut c_void) -> c_int;
    fn actql_native_owned_thread_join(owner: *mut c_void, control: *mut c_void) -> c_int;
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum Phase { Preparation, Current, Attributes, Start, AttributesClose, Join, Retirement }

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct Failure { pub phase: Phase, pub code: c_int }

#[derive(Debug)]
pub(super) enum Stopped { NeverStarted, Returned(thread::Result<()>) }

struct Payload {
    entry: unsafe fn(),
    attributes: UnsafeCell<MaybeUninit<libc::pthread_attr_t>>,
    result: UnsafeCell<Option<thread::Result<()>>>,
}

pub(super) struct OwnedHandlerThread {
    owner: *mut c_void,
    allocation: *mut c_void,
    payload: *mut Payload,
    control_bytes: usize,
    attempted: bool,
    native_attempted: bool,
    join_attempted: bool,
    stopped: bool,
    retirement_attempted: bool,
    attributes_initialized: bool,
    attributes_close_attempted: bool,
    pub failure: Option<Failure>,
    pub attributes_close_failure: Option<c_int>,
}

// SAFETY: The original synchronized provider controls creation and join. Only
// the owned handler writes the payload result; confirmed join precedes reading
// it. No Clone is available. The existing process owner excludes alias mutation
// and retirement until that join, including Rust/pthread TLS destructors.
unsafe impl Send for OwnedHandlerThread {}
unsafe impl Sync for OwnedHandlerThread {}

impl OwnedHandlerThread {
    pub fn prepare(entry: unsafe fn()) -> Result<Self, Failure> {
        let owner = unsafe { actql_native_owned_current() };
        if owner.is_null() { return Err(Failure { phase: Phase::Current, code: -1 }); }
        let control_bytes = unsafe { actql_native_owned_thread_control_bytes() };
        let alignment = unsafe { actql_native_owned_thread_control_alignment() }.max(align_of::<Payload>());
        if control_bytes == 0 || !alignment.is_power_of_two() {
            return Err(Failure { phase: Phase::Preparation, code: -1 });
        }
        let Some(prefix) = control_bytes.checked_add(alignment - 1).map(|n| n & !(alignment - 1)) else {
            return Err(Failure { phase: Phase::Preparation, code: -1 });
        };
        let Some(bytes) = prefix.checked_add(size_of::<Payload>()).filter(|n| *n <= isize::MAX as usize) else {
            return Err(Failure { phase: Phase::Preparation, code: -1 });
        };
        let mut allocation = ptr::null_mut();
        let code = unsafe { actql_native_owned_allocate(owner, bytes, alignment, &mut allocation) };
        if code != 0 || allocation.is_null() {
            // The existing original lease still owns any failed native extent.
            // No child has been issued and no replacement holding is acquired.
            return Err(Failure { phase: Phase::Preparation, code });
        }
        let payload = unsafe { allocation.cast::<u8>().add(prefix).cast::<Payload>() };
        unsafe { payload.write(Payload { entry, attributes: UnsafeCell::new(MaybeUninit::uninit()),
                                        result: UnsafeCell::new(None) }); }
        Ok(Self { owner, allocation, payload, control_bytes, attempted: false,
            native_attempted: false, join_attempted: false, stopped: false,
            retirement_attempted: false, attributes_initialized: false,
            attributes_close_attempted: false, failure: None, attributes_close_failure: None })
    }

    fn fail(&mut self, phase: Phase, code: c_int) -> Failure {
        let failure = Failure { phase, code };
        if self.failure.is_none() { self.failure = Some(failure); }
        failure
    }

    fn close_attributes(&mut self) -> Result<(), Failure> {
        if !self.attributes_initialized { return Ok(()); }
        if self.attributes_close_attempted {
            return Err(Failure { phase: Phase::AttributesClose,
                code: self.attributes_close_failure.unwrap_or(-2) });
        }
        self.attributes_close_attempted = true;
        let attributes = unsafe { (*self.payload).attributes.get().cast::<libc::pthread_attr_t>() };
        let code = unsafe { libc::pthread_attr_destroy(attributes) };
        if code != 0 {
            self.attributes_close_failure = Some(code);
            return Err(self.fail(Phase::AttributesClose, code));
        }
        self.attributes_initialized = false;
        Ok(())
    }

    pub fn start(&mut self) -> Result<(), Failure> {
        if self.attempted || self.retirement_attempted { return Err(self.fail(Phase::Start, -1)); }
        self.attempted = true;
        if unsafe { actql_native_owned_current() } != self.owner {
            return Err(self.fail(Phase::Current, -1));
        }
        let attributes = unsafe { (*self.payload).attributes.get().cast::<libc::pthread_attr_t>() };
        let code = unsafe { libc::pthread_attr_init(attributes) };
        if code != 0 { return Err(self.fail(Phase::Attributes, code)); }
        self.attributes_initialized = true;
        // Preserve pinned Rust1.90's selected Unix spawn stack input instead of
        // silently taking Darwin's different default pthread stack. This is an
        // operational thread attribute, NOT an arena grant or normal profile.
        let requested = std::env::var("RUST_MIN_STACK").ok()
            .and_then(|n| n.parse::<usize>().ok()).unwrap_or(2 * 1024 * 1024);
        let stack = requested.max(libc::PTHREAD_STACK_MIN);
        let mut code = unsafe { libc::pthread_attr_setstacksize(attributes, stack) };
        if code == libc::EINVAL {
            let page = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
            if page > 0 {
                let page = page as usize;
                if let Some(size) = stack.checked_add(page - 1).map(|n| n / page * page) {
                    code = unsafe { libc::pthread_attr_setstacksize(attributes, size) };
                }
            }
        }
        if code != 0 {
            let primary = self.fail(Phase::Attributes, code);
            let _pending = self.close_attributes(); // Stored independently, never acknowledged away.
            return Err(primary);
        }
        self.native_attempted = true;
        let code = unsafe { actql_native_owned_thread_start_configured(self.owner, self.allocation,
            self.control_bytes, attributes.cast(), enter, self.payload.cast()) };
        if code != 0 { self.fail(Phase::Start, code); }
        let attributes = self.close_attributes();
        if code != 0 { return Err(self.failure.unwrap()); }
        attributes
    }

    pub fn ready_in_original_scope(&self) -> bool {
        self.attempted && self.native_attempted && self.failure.is_none() &&
            !self.stopped && !self.retirement_attempted &&
            unsafe { actql_native_owned_current() } == self.owner
    }

    /// The existing process/runtime owner must FIRST confirm original port
    /// stop. This does not send a stop, cancel Run, destroy Engine or infer ACK.
    pub fn join_after_stop(&mut self) -> Result<Stopped, Failure> {
        if self.retirement_attempted || self.join_attempted { return Err(self.fail(Phase::Join, -2)); }
        self.join_attempted = true;
        if self.native_attempted {
            // Exact C pre-entry INVALID/BUSY returned before creating a child.
            // PHYSICAL_FAILURE may still own a child and MUST use original join.
            let known_no_start = self.failure.is_some_and(|e|
                e.phase == Phase::Start && matches!(e.code, -1 | -3));
            if !known_no_start {
                let code = unsafe { actql_native_owned_thread_join(self.owner, self.allocation) };
                if code != 0 { return Err(self.fail(Phase::Join, code)); }
            }
        }
        self.stopped = true;
        self.close_attributes()?;
        let result = unsafe { (*(*self.payload).result.get()).take() };
        self.retirement_attempted = true;
        let code = unsafe { actql_native_owned_retire(self.owner, self.allocation) };
        if code != 0 { return Err(self.fail(Phase::Retirement, code)); }
        self.allocation = ptr::null_mut();
        self.payload = ptr::null_mut();
        Ok(match result { Some(result) => Stopped::Returned(result), None => Stopped::NeverStarted })
    }
}

unsafe extern "C" fn enter(argument: *mut c_void) {
    // C has already bound the same-provider original scope BEFORE Rust reaches
    // this callback, spawn-hook-like allocations or thread-local destructors.
    let payload = unsafe { &*argument.cast::<Payload>() };
    let result = catch_unwind(AssertUnwindSafe(|| unsafe { (payload.entry)() }));
    unsafe { *payload.result.get() = Some(result); }
}

// Deliberately no implicit join/retirement in Drop: an ordinary Engine drop or
// a lost startup/join response is not process-global port stop. Raw payload,
// callback and panic aliases stay in the original extent/pin until the existing
// owner confirms stop and invokes join_after_stop. Never System-free them.
