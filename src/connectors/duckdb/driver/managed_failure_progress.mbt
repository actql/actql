///|
/// Physical actions for one failed managed DuckDB execution. The portable
/// driver owns their ordering; an environment adapter only performs the
/// selected action and reports the resulting observations.
priv enum ManagedDuckDBFailureAction {
  CancelManagedOutput
  CloseManagedOutputOwners
  ReclaimManagedOutput
  CloseManagedExecution
  AwaitManagedNativeStop
  SettleManagedExecution
  RefreshManagedExecutionCleanup
  AwaitManagedOutputCleanup
  ManagedFailureFinished
}

///|
/// Select the next action without conflating native settlement, provisional
/// output reclamation, or common task cleanup. A Store cleanup failure can
/// remain pending after the native operation has settled, and vice versa.
fn prepare_managed_duckdb_failure_step(
  output_cancel_attempted : Bool,
  output_owners_close_attempted : Bool,
  output_reclaim_attempted : Bool,
  execution_close_attempted : Bool,
  native_stopped : Bool,
  execution_settled : Bool,
  execution_cleanup_confirmed : Bool,
  output_reclaimed : Bool,
) -> ManagedDuckDBFailureAction {
  if !output_cancel_attempted {
    return CancelManagedOutput
  }
  if !output_owners_close_attempted {
    return CloseManagedOutputOwners
  }
  if !output_reclaim_attempted {
    return ReclaimManagedOutput
  }
  // Closing the common task revokes future logical use. It does not claim that
  // the native operation stopped or that provisional output was reclaimed.
  if !execution_close_attempted {
    return CloseManagedExecution
  }
  if !native_stopped {
    return AwaitManagedNativeStop
  }
  if !execution_settled {
    return SettleManagedExecution
  }
  if !execution_cleanup_confirmed {
    return RefreshManagedExecutionCleanup
  }
  if !output_reclaimed {
    return AwaitManagedOutputCleanup
  }
  ManagedFailureFinished
}

///|
/// Stable adapter projection. Codes choose local physical actions and are not
/// a persistent execution state or a wire protocol.
fn managed_duckdb_failure_action_code(
  action : ManagedDuckDBFailureAction,
) -> Int {
  match action {
    CancelManagedOutput => 0
    CloseManagedOutputOwners => 1
    ReclaimManagedOutput => 2
    CloseManagedExecution => 3
    AwaitManagedNativeStop => 4
    SettleManagedExecution => 5
    RefreshManagedExecutionCleanup => 6
    AwaitManagedOutputCleanup => 7
    ManagedFailureFinished => 8
  }
}

///|
/// Physical retry actions are selected separately so failure of one cleanup
/// owner never suppresses an independent cleanup attempt.
priv enum ManagedDuckDBFailureRetryAction {
  RetryManagedNativeCleanup
  RetryManagedOutputCleanup
  ResumeManagedFailureProgress
}

///|
/// Choose one retry action from current ownership and the attempts already
/// made by this retry call. Historical diagnostic errors do not become live
/// cleanup ownership.
fn prepare_managed_duckdb_failure_retry_step(
  native_pending : Bool,
  native_retry_attempted : Bool,
  output_pending : Bool,
  output_retry_attempted : Bool,
) -> ManagedDuckDBFailureRetryAction {
  if native_pending && !native_retry_attempted {
    return RetryManagedNativeCleanup
  }
  if output_pending && !output_retry_attempted {
    return RetryManagedOutputCleanup
  }
  ResumeManagedFailureProgress
}

///|
fn managed_duckdb_failure_retry_action_code(
  action : ManagedDuckDBFailureRetryAction,
) -> Int {
  match action {
    RetryManagedNativeCleanup => 0
    RetryManagedOutputCleanup => 1
    ResumeManagedFailureProgress => 2
  }
}

///|
/// Portable adapter projection for one failure-cleanup step.
pub fn managed_duckdb_failure_step_code(
  output_cancel_attempted : Bool,
  output_owners_close_attempted : Bool,
  output_reclaim_attempted : Bool,
  execution_close_attempted : Bool,
  native_stopped : Bool,
  execution_settled : Bool,
  execution_cleanup_confirmed : Bool,
  output_reclaimed : Bool,
) -> Int {
  managed_duckdb_failure_action_code(
    prepare_managed_duckdb_failure_step(
      output_cancel_attempted, output_owners_close_attempted, output_reclaim_attempted,
      execution_close_attempted, native_stopped, execution_settled, execution_cleanup_confirmed,
      output_reclaimed,
    ),
  )
}

///|
/// Portable adapter projection for one independent cleanup retry.
pub fn managed_duckdb_failure_retry_step_code(
  native_pending : Bool,
  native_retry_attempted : Bool,
  output_pending : Bool,
  output_retry_attempted : Bool,
) -> Int {
  managed_duckdb_failure_retry_action_code(
    prepare_managed_duckdb_failure_retry_step(
      native_pending, native_retry_attempted, output_pending, output_retry_attempted,
    ),
  )
}
