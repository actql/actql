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
/// An exact producer binding, not matching by CID or filesystem path.
fn native_strategy_retained_input(
  run : NativeStrategyComputeRun,
  input : @execution.ProducerRead,
) -> NativeComputeRetainedInput? {
  for entry in run.entries {
    guard entry.runtime.retained_output is Some(handle) &&
      entry.runtime.retained_profile is Some(profile) else {
      continue
    }
    if @execution.retained_producer_payload(handle, input) is Some(file) {
      return Some({
        file,
        wire: profile.wire,
        max_batch_bytes: profile.max_batch_bytes,
      })
    }
  }
  None
}

///|
/// Exact retained copy of a Result already completed by this Run. The
/// conversion reader must use this owner, not a path or matching content CID.
fn native_strategy_retained_result(
  run : NativeStrategyComputeRun,
  output : @execution.CompletedOutput,
) -> NativeComputeRetainedInput? {
  for entry in run.entries {
    guard entry.runtime.retained_output is Some(handle) &&
      entry.runtime.retained_profile is Some(profile) else {
      continue
    }
    if @execution.retained_completed_payload(handle, output) is Some(file) {
      return Some({
        file,
        wire: profile.wire,
        max_batch_bytes: profile.max_batch_bytes,
      })
    }
  }
  None
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
  retained_profile? : NativeStrategyRetainedOutputProfile,
  additional_retained_source? : (@execution.ProducerRead) -> NativeComputeRetainedInput?,
) -> Result[@execution.CompletedOutput, NativeStrategyComputeRunIssue] {
  if !run.accepting {
    database.close()
    return Err(Closed)
  }
  let runtime = match
    start_native_strategy_compute_runtime(
      setup,
      database,
      import_limits,
      transfer_bytes,
      execution_bytes,
      retained_profile?,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Start(issue))
  }
  run.entries.push({ runtime, released: false, })
  execute_native_strategy_compute_runtime(runtime, retained_source=input => {
    match native_strategy_retained_input(run, input) {
      Some(source) => Some(source)
      None =>
        match additional_retained_source {
          Some(resolve) => resolve(input)
          None => None
        }
    }
  }).map_err(issue => Execution(issue))
}

///|
pub fn native_strategy_compute_run_task_count(
  run : NativeStrategyComputeRun,
) -> Int {
  run.entries.length()
}

///|
/// Read the value and predicate measurements owned by the exact completed
/// task. This reports the product attempt rather than estimating work from a
/// fixture or from the selected capability.
fn native_strategy_compute_task_usage(
  run : NativeStrategyComputeRun,
  task : Int,
) -> (Int, Int, Int, Int, Int, Int)? {
  for entry in run.entries {
    if entry.runtime.task_index != task || entry.runtime.output is None {
      continue
    }
    let attempt = @duckdb_driver.captured_duckdb_attempt(entry.runtime.task)
    guard @duckdb_compute.duckdb_compute_measurement_usage(attempt)
      is Some((work, bytes, nodes)) &&
      @duckdb_compute.duckdb_compute_demand_usage(attempt) is Some(demand) else {
      return None
    }
    match demand {
      @duckdb.Comparison(usage) =>
        return Some(
          (
            work,
            bytes,
            nodes,
            usage.physical_work,
            usage.physical_bytes,
            usage.physical_nodes,
          ),
        )
      _ => return Some((work, bytes, nodes, 0, 0, 0))
    }
  }
  None
}

///|
/// Stop admission and release every runtime whose physical and common cleanup
/// facts are confirmed. Failures do not skip independent entries, and another
/// call retries only owners that remain unresolved.
pub fn close_native_strategy_compute_run(
  run : NativeStrategyComputeRun,
) -> Result[Bool, NativeStrategyComputeCleanupIssue] {
  run.accepting = false
  let mut pending = false
  let mut first_failure : NativeStrategyComputeCleanupIssue? = None
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
