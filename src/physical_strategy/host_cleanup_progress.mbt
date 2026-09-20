///|
/// Common progression for one Host cleanup invocation. Environment adapters
/// retry physical handles and await close operations; they do not choose the
/// ordering or decide whether unresolved ownership is complete.
pub(all) enum HostCleanupRuntimeAction {
  HostCleanupRetryKnown
  HostCleanupAwaitCloses
  HostCleanupPending
  HostCleanupFailed
  HostCleanupFinished
} derive(Eq, Debug)

///|
/// Common invocation state for one Host cleanup pass. Current physical
/// responsibility remains an observation supplied by the environment, while
/// the portable owner fixes when retries and close waits may occur.
struct HostCleanupProgress {
  mut initial_retry_done : Bool
  mut closes_awaited : Bool
  mut final_retry_done : Bool
}

///|
pub fn begin_host_cleanup_progress() -> HostCleanupProgress {
  { initial_retry_done: false, closes_awaited: false, final_retry_done: false, }
}

///|
pub fn record_host_cleanup_retry(progress : HostCleanupProgress) -> Bool {
  if !progress.initial_retry_done {
    progress.initial_retry_done = true
    true
  } else if !progress.final_retry_done {
    progress.final_retry_done = true
    true
  } else {
    false
  }
}

///|
pub fn record_host_cleanup_closes_awaited(
  progress : HostCleanupProgress,
) -> Bool {
  if !progress.initial_retry_done || progress.closes_awaited {
    false
  } else {
    progress.closes_awaited = true
    true
  }
}

///|
pub fn prepare_host_cleanup_progress_step(
  progress : HostCleanupProgress,
  closes_pending : Bool,
  known_cleanup_pending : Bool,
  unconfirmed_ownership : Bool,
  cleanup_failed : Bool,
) -> HostCleanupRuntimeAction {
  prepare_host_cleanup_step(
    progress.initial_retry_done,
    progress.closes_awaited,
    progress.final_retry_done,
    closes_pending,
    known_cleanup_pending,
    unconfirmed_ownership,
    cleanup_failed,
  )
}

///|
pub fn prepare_host_cleanup_step(
  initial_retry_done : Bool,
  closes_awaited : Bool,
  final_retry_done : Bool,
  closes_pending : Bool,
  known_cleanup_pending : Bool,
  unconfirmed_ownership : Bool,
  cleanup_failed : Bool,
) -> HostCleanupRuntimeAction {
  if !initial_retry_done {
    return HostCleanupRetryKnown
  }
  if closes_pending && !closes_awaited {
    return HostCleanupAwaitCloses
  }
  if !final_retry_done {
    return HostCleanupRetryKnown
  }
  if cleanup_failed {
    return HostCleanupFailed
  }
  if closes_pending || known_cleanup_pending || unconfirmed_ownership {
    return HostCleanupPending
  }
  HostCleanupFinished
}

///|
pub fn host_cleanup_runtime_action_code(
  action : HostCleanupRuntimeAction,
) -> Int {
  match action {
    HostCleanupRetryKnown => 0
    HostCleanupAwaitCloses => 1
    HostCleanupPending => 2
    HostCleanupFailed => 3
    HostCleanupFinished => 4
  }
}

///|
/// Current physical responsibility, not historical diagnostic errors,
/// determines whether Host cleanup remains pending.
pub fn host_cleanup_pending(
  closes_pending : Bool,
  known_cleanup_pending : Bool,
  unconfirmed_ownership : Bool,
) -> Bool {
  closes_pending || known_cleanup_pending || unconfirmed_ownership
}
