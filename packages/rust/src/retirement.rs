//! Physical retention of the same Core and its pending input cleanup.
//!
//! These notifications are not Run cancellation, cleanup ACKs or authority.
//! No business work, retry policy or replacement Core is executed here.
#![allow(dead_code)]

use std::{any::Any, sync::{Arc, Condvar, Mutex, mpsc::{self, SyncSender, TrySendError}},
          thread::{self, JoinHandle}, time::Duration};
use crate::{abi::CoreInstance, abi_generated::Imports, transfer::InputBuffer};

pub(crate) struct RetainedCore<H: Imports> {
    pub(crate) core: CoreInstance<H>,
    pub(crate) nonce: i64,
    pub(crate) inputs: Vec<InputBuffer>,
    pub(crate) cleanup_fuel: u64,
    pub(crate) failure_slots: usize,
    pub(crate) primary_failure: Option<Arc<anyhow::Error>>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CleanupFailureKind { Invocation, CallbackUnwind, WorkerUnwind }

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum CleanupProgress {
    Waiting,
    Pending { operation: &'static str, code: i32 },
    Failed(CleanupFailureKind),
    RetentionFull,
    Complete,
}

// An original panic payload may contain a hostile formatter or destructor.
// Do not inspect, stringify, clone or destroy it while custody is pending.
pub(crate) struct OpaqueCleanupUnwind {
    payload: Mutex<Box<dyn Any + Send>>,
}

#[derive(Clone)]
pub(crate) struct CleanupSnapshot {
    pub(crate) attempt: u64,
    pub(crate) progress: CleanupProgress,
    pub(crate) primary_failure: Option<Arc<anyhow::Error>>,
    pub(crate) first_cleanup_failure: Option<Arc<anyhow::Error>>,
    pub(crate) first_cleanup_unwind: Option<Arc<OpaqueCleanupUnwind>>,
    pub(crate) failure_slots: usize,
    pub(crate) occupied_failure_slots: usize,
}

enum HeldFailure {
    Reserved,
    Error(Arc<anyhow::Error>),
    Unwind(Arc<OpaqueCleanupUnwind>),
}

struct Observation {
    snapshot: Mutex<CleanupSnapshot>,
    changed: Condvar,
}

struct Shared<H: Imports> {
    retained: Mutex<Option<RetainedCore<H>>>,
    observation: Arc<Observation>,
    failures: Mutex<Box<[Option<HeldFailure>]>>,
    worker_unwind: Mutex<Option<Arc<OpaqueCleanupUnwind>>>,
    join_unwind: Mutex<Option<Arc<OpaqueCleanupUnwind>>>,
    // This is the same supervisor's physical custody, not another logical
    // owner. Only actual Core close releases it. Unexpected worker exit cannot
    // turn disappearance of ordinary handles into pending resource Drop.
    keeper: Mutex<Option<Arc<Shared<H>>>>,
}

// Progress observers and physical wakers do not themselves retain Core/Host.
// Their existence must not mask a lost supervisor custody reference.
#[derive(Clone)]
pub(crate) struct CleanupNotification {
    observation: Arc<Observation>,
    sender: SyncSender<()>,
}

impl CleanupNotification {
    // The bounded channel never waits for a Store, guest call or Host callback.
    // Full means an existing wake is queued, not that cleanup has completed.
    pub(crate) fn request(&self) -> Result<(), TrySendError<()>> {
        match self.sender.try_send(()) {
            Ok(()) | Err(TrySendError::Full(())) => Ok(()),
            Err(cause) => Err(cause),
        }
    }

    pub(crate) fn snapshot(&self) -> CleanupSnapshot {
        self.observation.snapshot.lock().unwrap().clone()
    }

    pub(crate) fn wait_for_update(&self, after: u64, timeout: Duration) -> Option<CleanupSnapshot> {
        let progress = self.observation.snapshot.lock().unwrap();
        let (progress, _) = self.observation.changed.wait_timeout_while(progress, timeout,
            |value| value.attempt <= after).unwrap();
        if progress.attempt > after { Some(progress.clone()) } else { None }
    }
}

pub(crate) struct RetirementSupervisor<H: Imports> {
    shared: Arc<Shared<H>>,
    notification: CleanupNotification,
    worker: Option<JoinHandle<()>>,
}

pub(crate) struct RetirementStartFailure<H: Imports> {
    pub(crate) cause: anyhow::Error,
    pub(crate) retained: RetainedCore<H>,
}

impl<H: Imports> RetainedCore<H> {
    fn advance(&mut self) -> wasmtime::Result<CleanupProgress> {
        self.core.begin_cleanup_budget(self.cleanup_fuel)?;
        for input in &mut self.inputs {
            if input.is_closed() { continue; }
            let code = self.core.close_input_buffer(input)?;
            if code != 0 { return Ok(CleanupProgress::Pending { operation: "buffer_close", code }); }
        }
        let code = self.core.close_transfer_pool(self.nonce)?;
        Ok(if code == 0 { CleanupProgress::Complete }
           else { CleanupProgress::Pending { operation: "buffer_close_pool", code } })
    }
}

impl<H: Imports + Send + 'static> RetirementSupervisor<H> {
    pub(crate) fn start(retained: RetainedCore<H>) -> Result<Self, RetirementStartFailure<H>> {
        let validation = (|| {
            anyhow::ensure!(retained.cleanup_fuel > 0, "Empty cleanup invocation budget");
            anyhow::ensure!(retained.failure_slots > 0, "Empty failure custody allocation");
            for input in &retained.inputs { retained.core.original_buffer(input)?; }
            Ok(())
        })();
        if let Err(cause) = validation { return Err(RetirementStartFailure { cause, retained }); }
        let mut failures = Vec::new();
        if let Err(cause) = failures.try_reserve_exact(retained.failure_slots) {
            return Err(RetirementStartFailure { cause: cause.into(), retained });
        }
        failures.resize_with(retained.failure_slots, || None);
        let observation = Arc::new(Observation {
            snapshot: Mutex::new(CleanupSnapshot { attempt: 0, progress: CleanupProgress::Waiting,
                primary_failure: retained.primary_failure.clone(), first_cleanup_failure: None,
                first_cleanup_unwind: None, failure_slots: retained.failure_slots, occupied_failure_slots: 0 }),
            changed: Condvar::new(),
        });
        let shared = Arc::new(Shared { retained: Mutex::new(Some(retained)),
            observation: observation.clone(), failures: Mutex::new(failures.into_boxed_slice()),
            worker_unwind: Mutex::new(None), join_unwind: Mutex::new(None), keeper: Mutex::new(None) });
        *shared.keeper.lock().unwrap() = Some(shared.clone());
        let (sender, receiver) = mpsc::sync_channel(1);
        let same = shared.clone();
        let keepalive = sender.clone();
        let worker = thread::Builder::new().name("actql-core-retirement".to_owned()).spawn(move || {
            let _keepalive = keepalive;
            let exited = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
              while receiver.recv().is_ok() {
                // A fixed slot is admitted before fuel reset or guest entry.
                // No fallible cleanup is called if its original error/panic
                // cannot be retained without destroying an earlier original.
                let reserved = {
                    let mut failures = same.failures.lock().unwrap();
                    failures.iter().position(Option::is_none).map(|index| {
                        failures[index] = Some(HeldFailure::Reserved);
                        index
                    })
                };
                let Some(reserved) = reserved else {
                    let mut snapshot = same.observation.snapshot.lock().unwrap();
                    snapshot.attempt = snapshot.attempt.saturating_add(1);
                    snapshot.progress = CleanupProgress::RetentionFull;
                    same.observation.changed.notify_all();
                    continue;
                };
                let mut holding = same.retained.lock().unwrap();
                let retained = holding.as_mut().expect("Retained until actual Core close");
                let (progress, failure, unwind) = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| retained.advance())) {
                    Ok(Ok(progress)) => (progress, None, None),
                    Ok(Err(cause)) => (CleanupProgress::Failed(CleanupFailureKind::Invocation), Some(Arc::new(cause)), None),
                    Err(payload) => (CleanupProgress::Failed(CleanupFailureKind::CallbackUnwind), None,
                        Some(Arc::new(OpaqueCleanupUnwind { payload: Mutex::new(payload) }))),
                };
                let occupied = {
                    let mut failures = same.failures.lock().unwrap();
                    let slot = &mut failures[reserved];
                    if !matches!(slot, Some(HeldFailure::Reserved)) { panic!("Original reserved failure slot changed"); }
                    *slot = failure.as_ref().map(|cause| HeldFailure::Error(cause.clone()))
                        .or_else(|| unwind.as_ref().map(|payload| HeldFailure::Unwind(payload.clone())));
                    failures.iter().filter(|slot| slot.is_some()).count()
                };
                let complete = progress == CleanupProgress::Complete;
                if complete { drop(holding.take()); }
                drop(holding);
                let mut snapshot = same.observation.snapshot.lock().unwrap();
                snapshot.attempt = snapshot.attempt.saturating_add(1);
                snapshot.progress = progress;
                snapshot.occupied_failure_slots = occupied;
                if snapshot.first_cleanup_failure.is_none() { snapshot.first_cleanup_failure = failure; }
                if snapshot.first_cleanup_unwind.is_none() { snapshot.first_cleanup_unwind = unwind; }
                same.observation.changed.notify_all();
                drop(snapshot);
                if complete {
                    drop(same.keeper.lock().unwrap().take());
                    return;
                }
                // Pending/error performs no automatic spin, fuel refill or
                // new work. A queued physical wake retries this same cleanup.
              }
            }));
            if let Err(payload) = exited {
                // This single supervisor-exit cell was allocated before spawn.
                // Recover poisoned metadata locks without formatting their
                // contents; do not touch or discard pending Core custody.
                let payload = Arc::new(OpaqueCleanupUnwind { payload: Mutex::new(payload) });
                *same.worker_unwind.lock().unwrap_or_else(|value| value.into_inner()) = Some(payload.clone());
                let occupied = same.failures.lock().unwrap_or_else(|value| value.into_inner())
                    .iter().filter(|slot| slot.is_some()).count();
                let mut snapshot = same.observation.snapshot.lock().unwrap_or_else(|value| value.into_inner());
                snapshot.attempt = snapshot.attempt.saturating_add(1);
                snapshot.progress = CleanupProgress::Failed(CleanupFailureKind::WorkerUnwind);
                snapshot.occupied_failure_slots = occupied;
                if snapshot.first_cleanup_unwind.is_none() { snapshot.first_cleanup_unwind = Some(payload); }
                same.observation.changed.notify_all();
            }
        });
        match worker {
            Ok(worker) => Ok(Self { shared, notification: CleanupNotification { observation, sender }, worker: Some(worker) }),
            Err(cause) => {
                let retained = shared.retained.lock().unwrap().take().expect("Spawn failure retains original Core");
                drop(shared.keeper.lock().unwrap().take());
                Err(RetirementStartFailure { cause: cause.into(), retained })
            }
        }
    }

    pub(crate) fn notification(&self) -> CleanupNotification { self.notification.clone() }

    #[cfg(test)]
    pub(crate) fn poison_failure_custody_for_test(&self) {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _guard = self.shared.failures.lock().unwrap();
            panic!("Injected supervisor custody lock failure");
        }));
    }

    pub(crate) fn join_completed(&mut self) -> wasmtime::Result<bool> {
        if self.notification.snapshot().progress != CleanupProgress::Complete { return Ok(false); }
        if let Some(worker) = self.worker.take() {
            if let Err(payload) = worker.join() {
                let payload = Arc::new(OpaqueCleanupUnwind { payload: Mutex::new(payload) });
                *self.shared.join_unwind.lock().unwrap() = Some(payload.clone());
                let mut snapshot = self.notification.observation.snapshot.lock().unwrap();
                if snapshot.first_cleanup_unwind.is_none() { snapshot.first_cleanup_unwind = Some(payload); }
                snapshot.progress = CleanupProgress::Failed(CleanupFailureKind::WorkerUnwind);
                anyhow::bail!("Original retirement worker unwound");
            }
        }
        Ok(true)
    }
}

impl<H: Imports> Drop for RetirementSupervisor<H> {
    fn drop(&mut self) {
        let _ = self.notification.request();
        // Handle detach is not ACK. The explicit same-owner retention lease
        // survives worker/handle disappearance until actual Core cleanup 0.
    }
}
