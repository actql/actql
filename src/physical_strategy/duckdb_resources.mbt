///|
priv struct NativeTaskResources {
  attempt : @duckdb_compute.DuckDBComputeAttempt
  execution : TaskExecution
  resident_output : ResidentPendingOutput?
}

///|
fn native_task_resource(
  run : CapturedDAG,
  attempt : @duckdb_compute.DuckDBComputeAttempt,
) -> (Int, NativeTaskResources)? {
  for task, value in run.native_resources {
    if value is Some(value) && physical_equal(value.attempt, attempt) {
      return Some((task, value))
    }
  }
  None
}

///|
/// Concrete attempt lookup delegates physical enforcement to the common driver.
pub fn charge_captured_duckdb_transfer(
  run : CapturedDAG,
  attempt : @duckdb_compute.DuckDBComputeAttempt,
  bytes : Int64,
) -> Result[Unit, @resources.LedgerIssue] {
  guard native_task_resource(run, attempt) is Some((_, resource)) else {
    return Err(ForeignOwner)
  }
  charge_task_execution_transfer(run, resource.execution, bytes)
}

///|
/// Actual transport settlement, not a cancellation request.
pub fn settle_captured_duckdb_native(
  run : CapturedDAG,
  attempt : @duckdb_compute.DuckDBComputeAttempt,
  confirmed : Bool,
) -> Result[Unit, @resources.LedgerIssue] {
  guard native_task_resource(run, attempt) is Some((_, resource)) else {
    return Err(ForeignOwner)
  }
  settle_task_execution(run, resource.execution, confirmed)
}

///|
pub fn close_captured_duckdb_task(
  run : CapturedDAG,
  attempt : @duckdb_compute.DuckDBComputeAttempt,
) -> Unit {
  guard native_task_resource(run, attempt) is Some((_, resource)) else {
    return
  }
  close_task_execution(run, resource.execution)
}
