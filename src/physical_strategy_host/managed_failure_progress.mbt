///|
/// Common progression actions for a failed managed execution. Environment
/// adapters perform the named physical operation and report the resulting
/// observations; they do not choose settlement or release ordering.
pub(all) enum ManagedFailureRuntimeAction {
  FailureCloseAdditional
  FailureCloseOperations
  FailureAwaitStop
  FailureSettleOperations
  FailureRefreshCleanup
  FailureFinished
} derive(Eq, Debug)

///|
/// Portable progress for one failed managed execution. Environment adapters
/// perform physical operations and record their observations here; they do
/// not own a parallel settlement or cleanup progression.
struct ManagedFailureProgress {
  mut additional_closed : Bool
  mut operations_close_attempted : Bool
  mut operations_closed : Bool
  mut cleanup_stopped : Bool
  mut execution_settled : Bool
  mut cleanup_refreshed : Bool
}

///|
pub fn begin_managed_failure_progress(
  additional_closed : Bool,
  execution_settled : Bool,
  cleanup_refreshed : Bool,
) -> ManagedFailureProgress {
  {
    additional_closed,
    operations_close_attempted: false,
    operations_closed: false,
    cleanup_stopped: false,
    execution_settled,
    cleanup_refreshed,
  }
}

///|
pub fn record_managed_failure_additional_closed(
  progress : ManagedFailureProgress,
) -> Bool {
  progress.additional_closed = true
  true
}

///|
pub fn record_managed_failure_operations_close_attempted(
  progress : ManagedFailureProgress,
) -> Bool {
  progress.operations_close_attempted = true
  true
}

///|
pub fn record_managed_failure_operations_closed(
  progress : ManagedFailureProgress,
) -> Bool {
  if !progress.operations_close_attempted {
    false
  } else {
    progress.operations_closed = true
    true
  }
}

///|
pub fn record_managed_failure_cleanup_stopped(
  progress : ManagedFailureProgress,
) -> Bool {
  if !progress.additional_closed || !progress.operations_close_attempted {
    false
  } else {
    progress.cleanup_stopped = true
    true
  }
}

///|
pub fn record_managed_failure_execution_settled(
  progress : ManagedFailureProgress,
) -> Bool {
  if !progress.cleanup_stopped && progress.operations_close_attempted {
    false
  } else {
    progress.execution_settled = true
    true
  }
}

///|
pub fn record_managed_failure_cleanup_refreshed(
  progress : ManagedFailureProgress,
) -> Bool {
  if !progress.execution_settled || !progress.operations_closed {
    false
  } else {
    progress.cleanup_refreshed = true
    true
  }
}

///|
pub fn prepare_managed_failure_progress_step(
  progress : ManagedFailureProgress,
) -> ManagedFailureRuntimeAction {
  prepare_managed_failure_step(
    progress.additional_closed,
    progress.operations_close_attempted,
    progress.operations_closed,
    progress.cleanup_stopped,
    progress.execution_settled,
    progress.cleanup_refreshed,
  )
}

///|
/// Decide one failure-cleanup step from confirmed physical observations.
/// Historical diagnostic errors do not become current cleanup ownership.
pub fn prepare_managed_failure_step(
  additional_closed : Bool,
  operations_close_attempted : Bool,
  operations_closed : Bool,
  cleanup_stopped : Bool,
  execution_settled : Bool,
  cleanup_refreshed : Bool,
) -> ManagedFailureRuntimeAction {
  if !additional_closed {
    return FailureCloseAdditional
  }
  if !operations_close_attempted {
    return FailureCloseOperations
  }
  if !cleanup_stopped {
    return FailureAwaitStop
  }
  if !execution_settled {
    return FailureSettleOperations
  }
  if !operations_closed {
    return FailureCloseOperations
  }
  if !cleanup_refreshed {
    return FailureRefreshCleanup
  }
  FailureFinished
}

///|
/// Stable adapter projection. Codes select physical actions and are not a
/// persistent execution state or wire protocol.
pub fn managed_failure_runtime_action_code(
  action : ManagedFailureRuntimeAction,
) -> Int {
  match action {
    FailureCloseAdditional => 0
    FailureCloseOperations => 1
    FailureAwaitStop => 2
    FailureSettleOperations => 3
    FailureRefreshCleanup => 4
    FailureFinished => 5
  }
}
