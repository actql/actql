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
