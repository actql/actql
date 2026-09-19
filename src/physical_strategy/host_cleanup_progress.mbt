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
