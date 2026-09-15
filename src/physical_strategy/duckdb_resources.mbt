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
/// Recover only the exact execution installed by the common start boundary.
/// No callback or caller-supplied reservation can be attached through this handle.
pub fn captured_duckdb_execution(task : CapturedDuckDBTask) -> TaskExecution {
  task.execution
}
