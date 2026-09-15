///|
/// Concrete bridge handle; the DAG retains only its common execution.
/// It cannot be reconstructed from a raw attempt, task number or equal content.
struct CapturedDuckDBTask {
  attempt : @duckdb_compute.DuckDBComputeAttempt
  execution : TaskExecution
  resident_output : Ref[ResidentPendingOutput?]
}

///|
fn captured_duckdb_task_matches(
  run : CapturedDAG,
  task : CapturedDuckDBTask,
) -> Bool {
  task_execution_matches(run, task.execution)
}

///|
/// Transport access only; this raw attempt cannot operate on the DAG ledger or
/// publish a DAG result without the exact enclosing execution handle.
pub fn captured_duckdb_attempt(
  task : CapturedDuckDBTask,
) -> @duckdb_compute.DuckDBComputeAttempt {
  task.attempt
}

///|
/// Concrete attempt lookup delegates physical enforcement to the common driver.
pub fn charge_captured_duckdb_transfer(
  run : CapturedDAG,
  resource : CapturedDuckDBTask,
  bytes : Int64,
) -> Result[Unit, @resources.LedgerIssue] {
  guard captured_duckdb_task_matches(run, resource) else {
    return Err(ForeignOwner)
  }
  charge_task_execution_transfer(run, resource.execution, bytes)
}

///|
/// Actual transport settlement, not a cancellation request.
pub fn settle_captured_duckdb_native(
  run : CapturedDAG,
  resource : CapturedDuckDBTask,
  confirmed : Bool,
) -> Result[Unit, @resources.LedgerIssue] {
  guard captured_duckdb_task_matches(run, resource) else {
    return Err(ForeignOwner)
  }
  settle_task_execution(run, resource.execution, confirmed)
}

///|
pub fn close_captured_duckdb_task(
  run : CapturedDAG,
  resource : CapturedDuckDBTask,
) -> Unit {
  guard captured_duckdb_task_matches(run, resource) else { return }
  close_task_execution(run, resource.execution)
}
