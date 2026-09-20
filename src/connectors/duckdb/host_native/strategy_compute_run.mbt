///|
/// Product owner for the common task runtimes of one native DuckDB strategy
/// Run. Physical databases stop after each transaction, while the common task
/// owners remain live until downstream consumers and publication have ended.
struct NativeStrategyComputeRun {
  entries : Array[NativeStrategyComputeRunEntry]
  mut accepting : Bool
}

///|
priv struct NativeStrategyComputeRunEntry {
  runtime : NativeStrategyComputeRuntime
  mut released : Bool
}

///|
pub(all) enum NativeStrategyComputeRunIssue {
  Closed
  Start(NativeStrategyComputeIssue)
  Execution(NativeStrategyComputeFailure)
}

///|
pub fn open_native_strategy_compute_run() -> NativeStrategyComputeRun {
  { entries: [], accepting: true, }
}

///|
/// Execute one already selected task and retain its common runtime owner. The
/// owner is recorded before physical execution, so a failed attempt cannot
/// lose cleanup responsibility.
pub fn execute_native_strategy_compute_task(
  run : NativeStrategyComputeRun,
  setup : @duckdb_driver.StrategyComputeHostConfiguration,
  database : @native_duckdb.Database,
  import_limits : NativeComputeImportLimits,
  transfer_bytes : Int64,
  execution_bytes : Int64,
) -> Result[@execution.CompletedOutput, NativeStrategyComputeRunIssue] {
  if !run.accepting {
    database.close()
    return Err(Closed)
  }
  let runtime = match
    start_native_strategy_compute_runtime(
      setup, database, import_limits, transfer_bytes, execution_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Start(issue))
  }
  run.entries.push({ runtime, released: false, })
  execute_native_strategy_compute_runtime(runtime).map_err(issue => {
    Execution(issue)
  })
}

///|
pub fn native_strategy_compute_run_task_count(
  run : NativeStrategyComputeRun,
) -> Int {
  run.entries.length()
}

///|
/// Stop admission and release every runtime whose physical and common cleanup
/// facts are confirmed. Failures do not skip independent entries, and another
/// call retries only owners that remain unresolved.
pub fn close_native_strategy_compute_run(
  run : NativeStrategyComputeRun,
) -> Result[Bool, @resources.LedgerIssue] {
  run.accepting = false
  let mut pending = false
  let mut first_failure : @resources.LedgerIssue? = None
  for offset in 0..<run.entries.length() {
    let entry = run.entries[run.entries.length() - offset - 1]
    if !entry.released {
      match close_native_strategy_compute_runtime(entry.runtime) {
        Ok(true) => entry.released = true
        Ok(false) => pending = true
        Err(issue) => {
          pending = true
          if first_failure is None {
            first_failure = Some(issue)
          }
        }
      }
    }
  }
  match first_failure {
    Some(issue) => Err(issue)
    None => Ok(!pending)
  }
}
