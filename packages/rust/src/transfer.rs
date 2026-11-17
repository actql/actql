//! Short, synchronous transfers through the existing Core buffer Owner.
#![allow(dead_code)]

use std::sync::Arc;
use crate::{abi::CoreInstance, abi_generated::Imports};

const BLOCK_BYTES: usize = 16_384;

// Numeric handles are private routing data. The original instance association
// is retained separately even if another instance has equal nonce/handle data.
pub(crate) struct InputBuffer {
    identity: Arc<()>,
    nonce: i64,
    pub(crate) handle: i32,
    bytes: usize,
    closed: bool,
}

impl InputBuffer {
    pub(crate) fn is_closed(&self) -> bool { self.closed }
}

#[derive(Debug)]
pub(crate) struct CoreFailure {
    pub(crate) operation: &'static str,
    pub(crate) code: i32,
}

impl std::fmt::Display for CoreFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} refused with original Core code {}", self.operation, self.code)
    }
}
impl std::error::Error for CoreFailure {}

fn success(operation: &'static str, code: i32) -> wasmtime::Result<()> {
    if code == 0 { Ok(()) } else { Err(CoreFailure { operation, code }.into()) }
}

impl<H: Imports> CoreInstance<H> {
    // The caller already owns the physical input and its measured holding.
    // Core admits the reservation; this method creates no Root or allowance.
    pub(crate) fn reserve_input_buffer(&mut self, nonce: i64, ticket: i32,
        bytes: usize, physical_copy_bytes: i64) -> wasmtime::Result<InputBuffer> {
        let length = i32::try_from(bytes)?;
        let handle = self.normal_call(|functions, store| functions.buffer_reserve.call(store,
            (nonce, ticket, length, physical_copy_bytes)))?;
        if handle <= 0 { return Err(CoreFailure { operation: "buffer_reserve", code: handle }.into()); }
        Ok(InputBuffer { identity: self.identity.clone(), nonce, handle, bytes, closed: false })
    }

    pub(crate) fn original_buffer(&self, buffer: &InputBuffer) -> wasmtime::Result<()> {
        anyhow::ensure!(Arc::ptr_eq(&self.identity, &buffer.identity) && !buffer.closed,
                        "Foreign or closed original input buffer");
        Ok(())
    }

    pub(crate) fn fill_input_buffer(&mut self, buffer: &InputBuffer) -> wasmtime::Result<()> {
        self.require_normal()?;
        self.original_buffer(buffer)?;
        for start in (0..buffer.bytes).step_by(BLOCK_BYTES) {
            let count = (buffer.bytes - start).min(BLOCK_BYTES);
            let args = (buffer.nonce, buffer.handle, i32::try_from(start)?, i32::try_from(count)?);
            let code = self.normal_call(|functions, store| functions.buffer_fill_block.call(store, args))?;
            success("buffer_fill_block", code)?;
        }
        Ok(())
    }

    pub(crate) fn seal_input_buffer(&mut self, buffer: &InputBuffer) -> wasmtime::Result<()> {
        self.original_buffer(buffer)?;
        let code = self.normal_call(|functions, store| functions.buffer_seal.call(store, (buffer.nonce, buffer.handle)))?;
        success("buffer_seal", code)
    }

    // No guest offset or memory slice escapes this operation. The mutable
    // Store borrow spans read_block and the immediate copy, with no callback,
    // guest reentry, memory growth or asynchronous suspension between them.
    pub(crate) fn read_input_block(&mut self, buffer: &InputBuffer, start: usize,
        destination: &mut [u8]) -> wasmtime::Result<()> {
        self.original_buffer(buffer)?;
        anyhow::ensure!(!destination.is_empty() && destination.len() <= BLOCK_BYTES &&
            start <= buffer.bytes && destination.len() <= buffer.bytes - start,
            "Invalid bounded original buffer read");
        let args = (buffer.nonce, buffer.handle, i32::try_from(start)?, i32::try_from(destination.len())?);
        let offset = self.normal_call(|functions, store| functions.buffer_read_block.call(store, args))?;
        if offset < 0 { return Err(CoreFailure { operation: "buffer_read_block", code: offset }.into()); }
        self.copy_memory_block(usize::try_from(offset)?, destination)?;
        Ok(())
    }

    // Pending/failed cleanup leaves this same buffer usable only under Core's
    // retained state. There is no automatic close on error and no Drop ACK.
    pub(crate) fn close_input_buffer(&mut self, buffer: &mut InputBuffer) -> wasmtime::Result<i32> {
        self.original_buffer(buffer)?;
        let code = self.close_buffer_owner(buffer.nonce, buffer.handle)?;
        if code == 0 { buffer.closed = true; }
        Ok(code)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use std::sync::{atomic::{AtomicBool, AtomicUsize, Ordering}, mpsc};
    use std::time::Duration;
    use wasmtime::Caller;
    use crate::abi::{StoreState, test_support};

    #[derive(Default)]
    struct PhysicalInputs {
        inputs: BTreeMap<i32, Arc<[u8]>>,
        copies: Vec<(i32, i32)>,
        scalar_reads: usize,
        cleanup_ready: bool,
        stop_ready: bool,
        short_copy: bool,
        panic_copy: bool,
        cleanup_signal: Option<Arc<AtomicBool>>,
        cleanup_fail_once: Option<Arc<AtomicBool>>,
        cleanup_block: Option<(mpsc::SyncSender<()>, mpsc::Receiver<()>)>,
        cleanup_display_trap: Option<Arc<AtomicUsize>>,
        cleanup_panic_payload: Option<Arc<AtomicUsize>>,
        cleanup_call_count: Option<Arc<AtomicUsize>>,
    }

    #[derive(Debug)]
    struct DisplayTrap(Arc<AtomicUsize>);
    impl std::fmt::Display for DisplayTrap {
        fn fmt(&self, _: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            self.0.fetch_add(1, Ordering::AcqRel);
            panic!("User error Display must not run during retained cleanup");
        }
    }
    impl std::error::Error for DisplayTrap {}

    struct PanicPayload(Arc<AtomicUsize>);
    impl Drop for PanicPayload {
        fn drop(&mut self) { self.0.fetch_add(1, Ordering::AcqRel); }
    }

    impl Imports for PhysicalInputs {
        fn input_copy(mut caller: Caller<'_, StoreState<Self>>, ticket: i32, start: i32,
            offset: i32, length: i32) -> wasmtime::Result<i32> {
            anyhow::ensure!(start >= 0 && offset >= 0 && (1..=16_384).contains(&length),
                            "Invalid physical copy bounds");
            let host = &mut caller.data_mut().host;
            assert!(!host.panic_copy, "Original physical copy callback panicked");
            let original = host.inputs.get(&ticket).ok_or_else(|| anyhow::anyhow!("Unknown original input"))?.clone();
            let start = usize::try_from(start)?;
            let count = usize::try_from(length)?;
            anyhow::ensure!(start <= original.len() && count <= original.len() - start,
                            "Physical copy exceeds original input");
            host.copies.push((i32::try_from(start)?, length));
            let copied = if host.short_copy { count - 1 } else { count };
            let memory = caller.get_export("memory").and_then(|value| value.into_memory())
                .ok_or_else(|| anyhow::anyhow!("Missing same-instance memory"))?;
            memory.write(&mut caller, usize::try_from(offset)?, &original[start..start + copied])?;
            Ok(i32::try_from(copied)?)
        }

        fn input_byte(mut caller: Caller<'_, StoreState<Self>>, _: i32, _: i32) -> wasmtime::Result<i32> {
            caller.data_mut().host.scalar_reads += 1;
            anyhow::bail!("No implicit scalar-transfer fallback")
        }

        fn input_cleanup(mut caller: Caller<'_, StoreState<Self>>, ticket: i32) -> wasmtime::Result<i32> {
            let host = &mut caller.data_mut().host;
            if let Some(count) = &host.cleanup_call_count { count.fetch_add(1, Ordering::AcqRel); }
            if let Some(observed) = host.cleanup_display_trap.take() {
                return Err(anyhow::Error::new(DisplayTrap(observed)));
            }
            if let Some(observed) = host.cleanup_panic_payload.take() {
                std::panic::panic_any(PanicPayload(observed));
            }
            if let Some((entered, release)) = host.cleanup_block.take() {
                entered.send(())?;
                release.recv_timeout(Duration::from_secs(5))?;
            }
            if host.cleanup_fail_once.as_ref().is_some_and(|signal| signal.swap(false, Ordering::AcqRel)) {
                anyhow::bail!("Original physical cleanup failure");
            }
            if !host.cleanup_ready && !host.cleanup_signal.as_ref().is_some_and(|signal| signal.load(Ordering::Acquire)) { return Ok(1); }
            anyhow::ensure!(host.inputs.remove(&ticket).is_some(), "Unknown original cleanup input");
            Ok(0)
        }

        fn reader_stop(caller: Caller<'_, StoreState<Self>>, ticket: i32, reader: i32) -> wasmtime::Result<i32> {
            let host = &caller.data().host;
            anyhow::ensure!(host.inputs.contains_key(&ticket) && reader > 0, "Foreign original reader");
            Ok(if host.stop_ready { 0 } else { 1 })
        }
    }

    fn pool(nonce: i64) -> CoreInstance<PhysicalInputs> {
        pool_with_module(nonce, test_support::actual_module())
    }

    fn pool_with_module(nonce: i64, module: &crate::abi::CompiledCore) -> CoreInstance<PhysicalInputs> {
        let mut core = module.instantiate(PhysicalInputs::default()).unwrap();
        // Explicit scalar diagnostic pool. This is not a normal Host/Run or
        // an imported execution child, and no unavailable grant is stubbed.
        assert_eq!(core.normal_call(|functions, store| functions.buffer_open.call(store, (nonce, 262_144, 16, 1_048_576, 100_000, 18, 16,
             32_000_000, 200_000_000, 16_777_216 + 262_144, 0))).unwrap(), 0);
        // A fresh diagnostic initialization uses the existing normal Host's
        // finite 1B bootstrap budget; this next scope selects its 32B operation
        // budget once. Neither is replenished inside a guest call or retry.
        core.begin_normal_budget(32_000_000_000).unwrap();
        core
    }

    fn input(core: &mut CoreInstance<PhysicalInputs>, nonce: i64, ticket: i32, bytes: Arc<[u8]>) -> InputBuffer {
        let length = bytes.len();
        assert!(core.host_mut().inputs.insert(ticket, bytes).is_none());
        core.reserve_input_buffer(nonce, ticket, length,
            i64::try_from(length + std::mem::size_of::<InputBuffer>()).unwrap()).unwrap()
    }

    #[test]
    fn block_round_trip_feeds_the_original_core_preparation() {
        let nonce = 8201; let mut core = pool(nonce);
        let mut payload = vec![b'"']; payload.extend(vec![b'x'; 32_768]);
        payload.extend(b"\\u0000/\xf0\x9f\x98\x80/e\xcc\x81\"\r\n");
        let original: Arc<[u8]> = payload.into();
        let mut buffer = input(&mut core, nonce, 41, original.clone());
        assert!(core.read_input_block(&buffer, 0, &mut [0u8; 1]).is_err());
        core.fill_input_buffer(&buffer).unwrap(); core.seal_input_buffer(&buffer).unwrap();
        assert_eq!(core.host().copies, [(0, 16_384), (16_384, 16_384), (32_768, 19)]);
        assert_eq!(core.host().scalar_reads, 0);
        for start in (0..original.len()).step_by(BLOCK_BYTES) {
            let count = (original.len() - start).min(BLOCK_BYTES);
            let mut block = vec![0u8; count]; core.read_input_block(&buffer, start, &mut block).unwrap();
            assert_eq!(block, &original[start..start + count]);
        }
        assert!(Arc::ptr_eq(core.host().inputs.get(&41).unwrap(), &original));
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), -9);
        core.host_mut().cleanup_ready = true;
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), 0);
        core.host_mut().cleanup_ready = false;
        let environment: Arc<[u8]> = include_bytes!("../tests/fixtures/check-environment.json").as_slice().into();
        let mut environment_input = input(&mut core, nonce, 42, environment);
        core.fill_input_buffer(&environment_input).unwrap(); core.seal_input_buffer(&environment_input).unwrap();
        let environment = core.normal_call(|functions, store| functions.program_install_environment.call(store, (nonce, environment_input.handle))).unwrap();
        assert!(environment > 0, "Original Core environment refusal: {environment}");
        let mut query = input(&mut core, nonce, 43, br#""SELECT 41 AS n |> RESULT answer""#.as_slice().into());
        core.fill_input_buffer(&query).unwrap(); core.seal_input_buffer(&query).unwrap();
        let preparation = core.normal_call(|functions, store| functions.program_reserve_preparation.call(store, (nonce, environment, query.handle, 2))).unwrap();
        assert!(preparation > 0);
        assert_eq!(core.normal_call(|functions, store| functions.program_prepare.call(store, (nonce, preparation))).unwrap(), 0);
        assert_eq!(core.normal_call(|functions, store| functions.program_prepared_results.call(store, (nonce, preparation))).unwrap(), 1);
        assert_eq!(core.close_preparation_owner(nonce, preparation).unwrap(), -9);
        core.host_mut().stop_ready = true;
        assert_eq!(core.close_preparation_owner(nonce, preparation).unwrap(), 0);
        assert_eq!(core.close_environment_owner(nonce, environment).unwrap(), 0);
        core.host_mut().cleanup_ready = true;
        assert_eq!(core.close_input_buffer(&mut query).unwrap(), 0);
        assert_eq!(core.close_input_buffer(&mut environment_input).unwrap(), 0);
        assert_eq!(core.close_transfer_pool(nonce).unwrap(), 0);
        assert_eq!(core.reserved_transfer_bytes(nonce).unwrap(), 0);
        assert_eq!(core.host().scalar_reads, 0);
    }

    #[test]
    fn equal_numeric_handles_from_another_instance_do_not_copy_or_read() {
        let nonce = 8202; let mut left = pool(nonce); let mut right = pool(nonce);
        let mut left_buffer = input(&mut left, nonce, 1, b"\"left\"".as_slice().into());
        let mut right_buffer = input(&mut right, nonce, 1, b"\"right\"".as_slice().into());
        assert_eq!(left_buffer.handle, right_buffer.handle);
        assert!(right.fill_input_buffer(&left_buffer).is_err());
        assert!(right.read_input_block(&left_buffer, 0, &mut [0u8; 1]).is_err());
        assert!(right.host().copies.is_empty());
        right.fill_input_buffer(&right_buffer).unwrap(); right.seal_input_buffer(&right_buffer).unwrap();
        let mut output = [0u8; 7]; right.read_input_block(&right_buffer, 0, &mut output).unwrap();
        assert_eq!(&output, b"\"right\"");
        for (core, buffer) in [(&mut left, &mut left_buffer), (&mut right, &mut right_buffer)] {
            core.host_mut().cleanup_ready = true;
            assert_eq!(core.close_input_buffer(buffer).unwrap(), 0);
            assert!(core.fill_input_buffer(buffer).is_err());
            assert_eq!(core.close_transfer_pool(nonce).unwrap(), 0);
        }
    }

    #[test]
    fn short_copy_failure_retains_the_original_cleanup_owner() {
        let nonce = 8203; let mut core = pool(nonce);
        let original: Arc<[u8]> = b"original".as_slice().into();
        let mut buffer = input(&mut core, nonce, 9, original.clone());
        core.host_mut().short_copy = true;
        let failure = core.fill_input_buffer(&buffer).unwrap_err();
        assert!(failure.downcast_ref::<CoreFailure>().unwrap().code < 0);
        assert!(core.normal_available(), "An ordinary Core refusal is not a hard trap");
        assert_eq!(core.host().copies, [(0, 8)]);
        assert_eq!(core.host().scalar_reads, 0);
        assert!(Arc::ptr_eq(core.host().inputs.get(&9).unwrap(), &original));
        assert!(core.allocated_transfer_bytes(nonce).unwrap() > 0);
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), -9);
        assert!(core.host().inputs.contains_key(&9));
        core.host_mut().cleanup_ready = true;
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), 0);
        assert!(!core.host().inputs.contains_key(&9));
        assert_eq!(core.close_transfer_pool(nonce).unwrap(), 0);
        assert_eq!(core.reserved_transfer_bytes(nonce).unwrap(), 0);
    }

    #[test]
    fn hard_trap_cannot_refill_normal_work_but_keeps_original_cleanup() {
        let nonce = 8204; let mut core = pool(nonce);
        let original: Arc<[u8]> = b"\"retained original\"".as_slice().into();
        let mut buffer = input(&mut core, nonce, 7, original.clone());
        let mut empty = input(&mut core, nonce, 8, b"".as_slice().into());
        core.begin_normal_budget(1).unwrap();
        let failure = core.fill_input_buffer(&buffer).unwrap_err();
        assert!(matches!(failure.downcast_ref::<wasmtime::Trap>(), Some(wasmtime::Trap::OutOfFuel)));
        assert!(!core.normal_available());
        let remaining = core.remaining_fuel().unwrap();
        assert!(core.begin_normal_budget(32_000_000_000).is_err());
        assert_eq!(core.remaining_fuel().unwrap(), remaining);
        let copies = core.host().copies.len();
        assert!(core.fill_input_buffer(&buffer).is_err());
        assert!(core.fill_input_buffer(&empty).is_err());
        assert!(core.reserve_input_buffer(nonce, 9, 1, 64).is_err());
        assert_eq!(core.host().copies.len(), copies);
        assert!(Arc::ptr_eq(core.host().inputs.get(&7).unwrap(), &original));
        core.begin_cleanup_budget(100_000_000).unwrap();
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), -9);
        assert!(!core.normal_available());
        assert!(core.host().inputs.contains_key(&7));
        core.host_mut().cleanup_ready = true;
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), 0);
        assert_eq!(core.close_input_buffer(&mut empty).unwrap(), 0);
        assert_eq!(core.close_transfer_pool(nonce).unwrap(), 0);
        assert_eq!(core.reserved_transfer_bytes(nonce).unwrap(), 0);
        assert!(core.begin_normal_budget(1).is_err());
    }

    #[test]
    fn callback_unwind_leaves_same_instance_cleanup_only() {
        let nonce = 8205; let mut core = pool(nonce);
        let original: Arc<[u8]> = b"\"callback original\"".as_slice().into();
        let mut buffer = input(&mut core, nonce, 11, original.clone());
        core.host_mut().panic_copy = true;
        let unwind = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            core.fill_input_buffer(&buffer).unwrap();
        }));
        assert!(unwind.is_err());
        assert!(!core.normal_available());
        assert!(Arc::ptr_eq(core.host().inputs.get(&11).unwrap(), &original));
        assert!(core.begin_normal_budget(32_000_000_000).is_err());
        core.begin_cleanup_budget(100_000_000).unwrap();
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), -9);
        core.host_mut().cleanup_ready = true;
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), 0);
        assert_eq!(core.close_transfer_pool(nonce).unwrap(), 0);
        assert_eq!(core.reserved_transfer_bytes(nonce).unwrap(), 0);
    }

    #[test]
    fn supervisor_retains_primary_and_originals_after_drop_without_blocking_notification() {
        use crate::retirement::{RetainedCore, RetirementSupervisor, CleanupProgress};
        let nonce = 8206; let mut core = pool(nonce);
        let original: Arc<[u8]> = b"\"original pending input\"".as_slice().into();
        let physical = Arc::downgrade(&original);
        let buffer = input(&mut core, nonce, 21, original);
        core.begin_normal_budget(1).unwrap();
        let primary = Arc::new(core.fill_input_buffer(&buffer).unwrap_err());
        assert!(matches!(primary.downcast_ref::<wasmtime::Trap>(), Some(wasmtime::Trap::OutOfFuel)));
        let ready = Arc::new(AtomicBool::new(false));
        core.host_mut().cleanup_signal = Some(ready.clone());
        core.host_mut().cleanup_fail_once = Some(Arc::new(AtomicBool::new(true)));
        let (entered_send, entered) = mpsc::sync_channel(1);
        let (release, release_receive) = mpsc::sync_channel(1);
        core.host_mut().cleanup_block = Some((entered_send, release_receive));
        let supervisor = match RetirementSupervisor::start(RetainedCore {
            core, nonce, inputs: vec![buffer], cleanup_fuel: 100_000_000, failure_slots: 4,
            primary_failure: Some(primary.clone()),
        }) { Ok(value) => value, Err(failure) => panic!("{}", failure.cause) };
        let notification = supervisor.notification();
        notification.request().unwrap();
        entered.recv_timeout(Duration::from_secs(5)).unwrap();
        // The actual Core Store is inside a blocked original Host callback.
        // A wake and Drop both return before releasing that callback.
        notification.request().unwrap();
        drop(supervisor);
        assert!(physical.upgrade().is_some());
        assert_eq!(notification.snapshot().attempt, 0);
        release.send(()).unwrap();
        let mut snapshot = notification.wait_for_update(0, Duration::from_secs(5)).unwrap();
        while !matches!(snapshot.progress, CleanupProgress::Pending { .. }) {
            snapshot = notification.wait_for_update(snapshot.attempt, Duration::from_secs(5)).unwrap();
        }
        assert!(Arc::ptr_eq(snapshot.primary_failure.as_ref().unwrap(), &primary));
        assert_eq!(snapshot.first_cleanup_failure.as_ref().unwrap().root_cause().to_string(), "Original physical cleanup failure");
        assert!(physical.upgrade().is_some());
        ready.store(true, Ordering::Release);
        notification.request().unwrap();
        snapshot = notification.wait_for_update(snapshot.attempt, Duration::from_secs(5)).unwrap();
        assert_eq!(snapshot.progress, CleanupProgress::Complete);
        assert!(Arc::ptr_eq(snapshot.primary_failure.as_ref().unwrap(), &primary));
        assert!(snapshot.first_cleanup_failure.is_some());
        assert!(physical.upgrade().is_none());
    }

    #[test]
    fn supervisor_requires_actual_cleanup_before_join_and_preserves_failed_start_owner() {
        use crate::retirement::{RetainedCore, RetirementSupervisor, CleanupProgress};
        let nonce = 8207; let mut core = pool(nonce);
        let original: Arc<[u8]> = b"\"same start owner\"".as_slice().into();
        let physical = Arc::downgrade(&original);
        let buffer = input(&mut core, nonce, 22, original);
        let ready = Arc::new(AtomicBool::new(false));
        core.host_mut().cleanup_signal = Some(ready.clone());
        let failure = match RetirementSupervisor::start(RetainedCore {
            core, nonce, inputs: vec![buffer], cleanup_fuel: 0, failure_slots: 4, primary_failure: None,
        }) { Ok(_) => panic!("Invalid cleanup budget admitted"), Err(failure) => failure };
        assert!(physical.upgrade().is_some());
        assert!(failure.cause.to_string().contains("Empty cleanup invocation budget"));
        let mut retained = failure.retained;
        retained.cleanup_fuel = 100_000_000;
        let mut supervisor = match RetirementSupervisor::start(retained) {
            Ok(value) => value, Err(failure) => panic!("{}", failure.cause),
        };
        let notification = supervisor.notification();
        assert!(!supervisor.join_completed().unwrap());
        notification.request().unwrap();
        let pending = notification.wait_for_update(0, Duration::from_secs(5)).unwrap();
        assert!(matches!(pending.progress, CleanupProgress::Pending { code: -9, .. }));
        assert!(!supervisor.join_completed().unwrap());
        assert!(physical.upgrade().is_some());
        ready.store(true, Ordering::Release);
        notification.request().unwrap();
        let complete = notification.wait_for_update(pending.attempt, Duration::from_secs(5)).unwrap();
        assert_eq!(complete.progress, CleanupProgress::Complete);
        assert!(supervisor.join_completed().unwrap());
        assert!(physical.upgrade().is_none());
    }

    #[test]
    fn custody_error_display_is_never_called_before_original_retirement() {
        use crate::retirement::{RetainedCore, RetirementSupervisor, CleanupProgress};
        // Without Wasm backtrace context the original Host error is the top
        // error. A safe outer backtrace formatter must not hide this counter.
        let nonce = 8208; let mut core = pool_with_module(nonce, test_support::actual_module_without_backtrace());
        let original: Arc<[u8]> = b"\"opaque failure original\"".as_slice().into();
        let physical = Arc::downgrade(&original);
        let buffer = input(&mut core, nonce, 23, original);
        let primary = Arc::new(anyhow::anyhow!("Distinct original primary failure"));
        let ready = Arc::new(AtomicBool::new(false));
        let formats = Arc::new(AtomicUsize::new(0));
        core.host_mut().cleanup_signal = Some(ready.clone());
        core.host_mut().cleanup_display_trap = Some(formats.clone());
        let supervisor = match RetirementSupervisor::start(RetainedCore {
            core, nonce, inputs: vec![buffer], cleanup_fuel: 100_000_000, failure_slots: 4,
            primary_failure: Some(primary.clone()),
        }) { Ok(value) => value, Err(_) => panic!("Original retirement constructor refused") };
        let notification = supervisor.notification();
        notification.request().unwrap();
        let observed = notification.wait_for_update(0, Duration::from_secs(5));
        assert_eq!(formats.load(Ordering::Acquire), 0, "Retained cleanup invoked user Display");
        let failed = observed.expect("Opaque cleanup error must be recorded without formatting");
        assert!(matches!(failed.progress, CleanupProgress::Failed(_)));
        let first = failed.first_cleanup_failure.clone().unwrap();
        assert!(first.root_cause().downcast_ref::<DisplayTrap>().is_some());
        assert!(Arc::ptr_eq(failed.primary_failure.as_ref().unwrap(), &primary));
        drop(supervisor);
        let pending = notification.wait_for_update(failed.attempt, Duration::from_secs(5)).unwrap();
        assert!(matches!(pending.progress, CleanupProgress::Pending { code: -9, .. }));
        assert!(physical.upgrade().is_some());
        assert!(Arc::ptr_eq(pending.first_cleanup_failure.as_ref().unwrap(), &first));
        assert!(Arc::ptr_eq(pending.primary_failure.as_ref().unwrap(), &primary));
        ready.store(true, Ordering::Release);
        notification.request().unwrap();
        let complete = notification.wait_for_update(pending.attempt, Duration::from_secs(5)).unwrap();
        assert_eq!(complete.progress, CleanupProgress::Complete);
        assert!(Arc::ptr_eq(complete.first_cleanup_failure.as_ref().unwrap(), &first));
        assert!(Arc::ptr_eq(complete.primary_failure.as_ref().unwrap(), &primary));
        assert_eq!(formats.load(Ordering::Acquire), 0);
        assert!(physical.upgrade().is_none());
    }

    #[test]
    fn custody_panic_payload_is_not_destroyed_while_original_cleanup_is_pending() {
        use crate::retirement::{RetainedCore, RetirementSupervisor, CleanupProgress};
        let nonce = 8209; let mut core = pool(nonce);
        let original: Arc<[u8]> = b"\"opaque unwind original\"".as_slice().into();
        let physical = Arc::downgrade(&original);
        let buffer = input(&mut core, nonce, 24, original);
        let primary = Arc::new(anyhow::anyhow!("Distinct original primary before unwind"));
        let ready = Arc::new(AtomicBool::new(false));
        let payload_drops = Arc::new(AtomicUsize::new(0));
        core.host_mut().cleanup_signal = Some(ready.clone());
        core.host_mut().cleanup_panic_payload = Some(payload_drops.clone());
        let supervisor = match RetirementSupervisor::start(RetainedCore {
            core, nonce, inputs: vec![buffer], cleanup_fuel: 100_000_000, failure_slots: 4,
            primary_failure: Some(primary.clone()),
        }) { Ok(value) => value, Err(_) => panic!("Original retirement constructor refused") };
        let notification = supervisor.notification();
        notification.request().unwrap();
        let failed = notification.wait_for_update(0, Duration::from_secs(5)).unwrap();
        assert!(matches!(failed.progress, CleanupProgress::Failed(_)));
        assert_eq!(payload_drops.load(Ordering::Acquire), 0, "Pending custody destroyed original panic payload");
        drop(supervisor);
        let pending = notification.wait_for_update(failed.attempt, Duration::from_secs(5)).unwrap();
        assert!(matches!(pending.progress, CleanupProgress::Pending { code: -9, .. }));
        assert!(physical.upgrade().is_some());
        assert_eq!(payload_drops.load(Ordering::Acquire), 0);
        assert!(Arc::ptr_eq(pending.primary_failure.as_ref().unwrap(), &primary));
        ready.store(true, Ordering::Release);
        notification.request().unwrap();
        let complete = notification.wait_for_update(pending.attempt, Duration::from_secs(5)).unwrap();
        assert_eq!(complete.progress, CleanupProgress::Complete);
        assert!(Arc::ptr_eq(complete.primary_failure.as_ref().unwrap(), &primary));
        assert!(physical.upgrade().is_none());
    }

    #[test]
    fn bounded_custody_refuses_before_another_cleanup_and_exposes_unexpected_worker_exit() {
        use crate::retirement::{RetainedCore, RetirementSupervisor, CleanupProgress, CleanupFailureKind};
        let nonce = 8210; let mut core = pool(nonce);
        let original: Arc<[u8]> = b"\"bounded retained original\"".as_slice().into();
        let physical = Arc::downgrade(&original);
        let buffer = input(&mut core, nonce, 25, original);
        let primary = Arc::new(anyhow::anyhow!("Original primary before custody exhaustion"));
        let ready = Arc::new(AtomicBool::new(false));
        let calls = Arc::new(AtomicUsize::new(0));
        core.host_mut().cleanup_signal = Some(ready.clone());
        core.host_mut().cleanup_call_count = Some(calls.clone());
        core.host_mut().cleanup_fail_once = Some(Arc::new(AtomicBool::new(true)));
        let mut supervisor = match RetirementSupervisor::start(RetainedCore {
            core, nonce, inputs: vec![buffer], cleanup_fuel: 100_000_000, failure_slots: 1,
            primary_failure: Some(primary.clone()),
        }) { Ok(value) => value, Err(_) => panic!("Finite custody allocation refused") };
        let notification = supervisor.notification();
        notification.request().unwrap();
        let failed = notification.wait_for_update(0, Duration::from_secs(5)).unwrap();
        assert_eq!(failed.progress, CleanupProgress::Failed(CleanupFailureKind::Invocation));
        assert_eq!(failed.failure_slots, 1);
        assert_eq!(failed.occupied_failure_slots, 1);
        let first = failed.first_cleanup_failure.clone().unwrap();
        assert_eq!(calls.load(Ordering::Acquire), 1);
        // Actual physical cleanup is now ready. No further guest invocation
        // may occur without space to keep its possible original failure.
        ready.store(true, Ordering::Release);
        notification.request().unwrap();
        let full = notification.wait_for_update(failed.attempt, Duration::from_secs(5)).unwrap();
        assert_eq!(full.progress, CleanupProgress::RetentionFull);
        assert_eq!(full.occupied_failure_slots, 1);
        assert_eq!(calls.load(Ordering::Acquire), 1);
        assert!(physical.upgrade().is_some());
        assert!(Arc::ptr_eq(full.first_cleanup_failure.as_ref().unwrap(), &first));
        assert!(Arc::ptr_eq(full.primary_failure.as_ref().unwrap(), &primary));
        assert!(!supervisor.join_completed().unwrap());
        // Inject an unexpected supervisor metadata fault, outside the caught
        // guest callback. This is not a Host cleanup failure or a success.
        supervisor.poison_failure_custody_for_test();
        notification.request().unwrap();
        let exited = notification.wait_for_update(full.attempt, Duration::from_secs(5)).unwrap();
        assert_eq!(exited.progress, CleanupProgress::Failed(CleanupFailureKind::WorkerUnwind));
        assert!(exited.first_cleanup_unwind.is_some());
        assert!(Arc::ptr_eq(exited.first_cleanup_failure.as_ref().unwrap(), &first));
        assert!(Arc::ptr_eq(exited.primary_failure.as_ref().unwrap(), &primary));
        assert!(!supervisor.join_completed().unwrap());
        drop(supervisor);
        assert_eq!(calls.load(Ordering::Acquire), 1);
        assert!(physical.upgrade().is_some());
        // Terminal pending is deliberate. No recovery/funding or physical ACK
        // is fabricated to make this negative diagnostic release its originals.
    }
}
