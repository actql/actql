///|
/// Product owner for one configured Local/DuckDB strategy Run on the native
/// target. The portable configured Host chooses the exact implementation;
/// this owner only connects that choice to synchronous Local execution or a
/// native DuckDB database and retains every common task owner.
struct NativeStandardStrategyRun {
  dispatch : @duckdb_standard_host.StrategyHostDispatch
  library : @native_duckdb.Library?
  runtimes : NativeStrategyComputeRun
  local_owners : Array[NativeStrategyLocalOwner]
  unfiled_local_owners : Array[NativeStrategyUnfiledLocalOwner]
  import_limits : NativeComputeImportLimits
  transfer_bytes : Int64
  database_memory_bytes : Int64
  database_path : String
  retained_profile : NativeStrategyRetainedOutputProfile?
  mut accepting : Bool
  mut complete : Bool
  mut dispatch_stopped : Bool
}

///|
pub(all) enum NativeStandardStrategyRunIssue {
  Closed
  InvalidSelection
  DuckDBUnavailable
  Dispatch(@duckdb_standard_host.DispatchIssue)
  Database(@native_duckdb.NativeDuckDBIssue)
  DuckDB(NativeStrategyComputeRunIssue)
  Local(NativeStrategyLocalIssue)
}

///|
/// One exact task completed by the configured standard Host. The selected
/// Connector remains private to the Host; remote and publication adapters
/// receive only the checked task index and its admitted output.
pub(all) struct NativeStandardStrategyTaskCompletion {
  task : Int
  output : @execution.CompletedOutput
  usage : NativeStandardStrategyTaskUsage?
  holding : NativeStandardStrategyTaskHolding?
}

///|
/// The sealed independent representation of this exact completed output.
pub(all) struct NativeStandardStrategyTaskHolding {
  rows : Int
  rows_cid : String
  bytes : Int64
}

///|
/// Product measurements for the completed task's actual implementation.
/// Logical obligations and ledger capacity remain separate accounting axes.
pub(all) struct NativeStandardStrategyTaskUsage {
  measurement_work : Int
  measurement_bytes : Int
  measurement_nodes : Int
  comparison_work : Int
  comparison_bytes : Int
  comparison_nodes : Int
}

///|
fn native_standard_task_usage(
  measured : (Int, Int, Int, Int, Int, Int),
) -> NativeStandardStrategyTaskUsage {
  {
    measurement_work: measured.0,
    measurement_bytes: measured.1,
    measurement_nodes: measured.2,
    comparison_work: measured.3,
    comparison_bytes: measured.4,
    comparison_nodes: measured.5,
  }
}

///|
fn native_standard_task_holding(
  run : NativeStandardStrategyRun,
  output : @execution.CompletedOutput,
) -> NativeStandardStrategyTaskHolding? {
  guard native_standard_retained_result(run, output) is Some(source) &&
    source.file.sealed_content() is Some((rows_cid, bytes)) else {
    return None
  }
  Some({ rows: @execution.completed_row_count(output), rows_cid, bytes, })
}

///|
/// Failures from the standard native application boundary. A publication
/// commit failure returns the exact prepared owner so the caller can retry or
/// cancel without re-executing the Program.
pub(all) enum NativeStandardRunPublicationIssue {
  Strategy(NativeStandardStrategyRunIssue)
  RetainedConversion(Int, NativeComputeExecutionIssue)
  Preparation(@native_publication.NativeCapturedRunPublicationPreparationIssue)
  Publication(
    @native_publication.NativePreparedCapturedRunPublication,
    @native_publication.NativeRunPublicationIssue
  )
}

///|
pub fn open_native_standard_strategy_run(
  dispatch : @duckdb_standard_host.StrategyHostDispatch,
  import_limits : NativeComputeImportLimits,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  library? : @native_duckdb.Library? = None,
  database_path? : String = "",
  retained_profile? : NativeStrategyRetainedOutputProfile,
) -> Result[NativeStandardStrategyRun, NativeStandardStrategyRunIssue] {
  if transfer_bytes < 0 || execution_bytes <= 0 {
    return Err(InvalidSelection)
  }
  if retained_profile is Some(profile) && profile.max_file_bytes <= 0L {
    return Err(InvalidSelection)
  }
  Ok({
    dispatch,
    library,
    runtimes: open_native_strategy_compute_run(),
    local_owners: [],
    unfiled_local_owners: [],
    import_limits,
    transfer_bytes,
    database_memory_bytes: execution_bytes,
    database_path,
    retained_profile,
    accepting: true,
    complete: false,
    dispatch_stopped: false,
  })
}

///|
fn NativeStandardStrategyRun::stop_dispatch(
  self : NativeStandardStrategyRun,
) -> Unit {
  if !self.dispatch_stopped {
    @duckdb_standard_host.stop_strategy_dispatch(self.dispatch)
    self.dispatch_stopped = true
  }
}

///|
/// Execute one checked-ready task through the exact implementation selected by
/// the portable Host. `None` means the Run has no remaining task. Failure
/// stops admission but leaves task runtimes in this owner until explicit
/// cleanup confirms their release.
pub fn execute_next_native_standard_strategy_task(
  run : NativeStandardStrategyRun,
) -> Result[
  NativeStandardStrategyTaskCompletion?,
  NativeStandardStrategyRunIssue,
] {
  if !run.accepting {
    return Err(Closed)
  }
  let prepared = match
    @duckdb_standard_host.prepare_next_dispatch(run.dispatch) {
    Ok(value) => value
    Err(issue) => {
      run.accepting = false
      run.stop_dispatch()
      return Err(Dispatch(issue))
    }
  }
  guard prepared is Some(task) else {
    run.accepting = false
    run.complete = true
    run.stop_dispatch()
    return Ok(None)
  }
  let task_index = @duckdb_standard_host.dispatch_task(task)
  guard @duckdb_standard_host.dispatch_registration(task) is Some(selected) else {
    run.accepting = false
    run.stop_dispatch()
    return Err(InvalidSelection)
  }
  if physical_equal(
      selected,
      @duckdb_standard_host.dispatch_local_registration(run.dispatch),
    ) {
    if run.retained_profile is Some(profile) {
      let operations = match @duckdb_standard_host.take_local_dispatch(task) {
        Ok(value) => value
        Err(issue) => {
          run.accepting = false
          run.stop_dispatch()
          return Err(Dispatch(issue))
        }
      }
      let owner = match
        start_native_strategy_local_owner(operations, profile, task_index) {
        Ok(value) => value
        Err(issue) => {
          run.unfiled_local_owners.push({
            operations,
            closed: false,
            settled: false,
          })
          run.accepting = false
          run.stop_dispatch()
          return Err(Local(issue))
        }
      }
      run.local_owners.push(owner)
      match
        execute_native_strategy_local_owner(owner, input => {
          for previous in run.local_owners {
            if native_strategy_local_input_source(previous, input)
              is Some(source) {
              return Some(source)
            }
          }
          native_strategy_retained_input(run.runtimes, input)
        }) {
        Ok(_) => ()
        Err(issue) => {
          run.accepting = false
          run.stop_dispatch()
          return Err(Local(issue))
        }
      }
    } else {
      match @duckdb_standard_host.execute_synchronous_dispatch(task) {
        Err(issue) => {
          run.accepting = false
          run.stop_dispatch()
          return Err(Dispatch(issue))
        }
        Ok(_) => ()
      }
    }
    guard @strategy.captured_task_target(
        @duckdb_standard_host.dispatch_run(run.dispatch),
        task_index,
      )
      is Some(target) &&
      @strategy.captured_task_output(
        @duckdb_standard_host.dispatch_run(run.dispatch),
        task_index,
        target,
      )
      is Some(output) else {
      run.accepting = false
      run.stop_dispatch()
      return Err(InvalidSelection)
    }
    let usage = if run.retained_profile is Some(_) {
      let last = run.local_owners[run.local_owners.length() - 1]
      let measured = (last.operations.guard_usage)()
      if measured.length() == 3 {
        Some(
          native_standard_task_usage(
            (measured[0], measured[1], measured[2], 0, 0, 0),
          ),
        )
      } else {
        None
      }
    } else {
      None
    }
    return Ok(
      Some({
        task: task_index,
        output,
        usage,
        holding: native_standard_task_holding(run, output),
      }),
    )
  }
  if !physical_equal(
      selected,
      @duckdb_standard_host.dispatch_duckdb_registration(run.dispatch),
    ) {
    run.accepting = false
    run.stop_dispatch()
    return Err(InvalidSelection)
  }
  let setup = match @duckdb_standard_host.take_native_dispatch(task) {
    Ok(value) => value
    Err(issue) => {
      run.accepting = false
      run.stop_dispatch()
      return Err(Dispatch(issue))
    }
  }
  guard run.library is Some(library) else {
    run.accepting = false
    run.stop_dispatch()
    return Err(DuckDBUnavailable)
  }
  // The driver reserves this engine budget plus its separately measured
  // transport/receiving scratch through the common execution ledger.
  let database = match
    library.open_database(
      {
        memory_bytes: run.database_memory_bytes,
        threads: 1,
        external_access: false,
        read_only: false,
      },
      path=run.database_path,
    ) {
    Ok(value) => value
    Err(issue) => {
      run.accepting = false
      run.stop_dispatch()
      return Err(Database(issue))
    }
  }
  match
    execute_native_strategy_compute_task(
      run.runtimes,
      setup,
      database,
      run.import_limits,
      run.transfer_bytes,
      run.database_memory_bytes,
      retained_profile?=run.retained_profile,
      additional_retained_source=input => {
        for owner in run.local_owners {
          if native_strategy_local_input_source(owner, input) is Some(source) {
            return Some(source)
          }
        }
        None
      },
    ) {
    Ok(output) =>
      Ok(
        Some({
          task: task_index,
          output,
          usage: native_strategy_compute_task_usage(run.runtimes, task_index).map(
            native_standard_task_usage,
          ),
          holding: native_standard_task_holding(run, output),
        }),
      )
    Err(issue) => {
      run.accepting = false
      run.stop_dispatch()
      Err(DuckDB(issue))
    }
  }
}

///|
/// Execute every checked-ready task through the one-task boundary available to
/// remote dispatch adapters. There is no second selection or completion path.
pub fn execute_native_standard_strategy_run(
  run : NativeStandardStrategyRun,
) -> Result[Unit, NativeStandardStrategyRunIssue] {
  while true {
    match execute_next_native_standard_strategy_task(run) {
      Ok(Some(_)) => continue
      Ok(None) => return Ok(())
      Err(issue) => return Err(issue)
    }
  } nobreak {
    Err(InvalidSelection)
  }
}

///|
fn native_standard_retained_result(
  run : NativeStandardStrategyRun,
  output : @execution.CompletedOutput,
) -> NativeComputeRetainedInput? {
  if native_strategy_retained_result(run.runtimes, output) is Some(source) {
    return Some(source)
  }
  for owner in run.local_owners {
    if native_strategy_local_result_source(owner, output) is Some(source) {
      return Some(source)
    }
  }
  None
}

///|
/// Consume an exact completed task through a fresh verified file reader.
/// The bounded projection is shared with formal publication and never adopts
/// a caller-provided path or a matching CID from another occurrence.
pub fn read_native_standard_task_output(
  run : NativeStandardStrategyRun,
  task : Int,
  max_rows : Int,
  values : @execution.ValueLimits,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
) -> Result[@execution.CompletedOutput, NativeStandardRunPublicationIssue] {
  let captured = @duckdb_standard_host.dispatch_run(run.dispatch)
  guard @strategy.captured_task_target(captured, task) is Some(target) &&
    @strategy.captured_task_output(captured, task, target) is Some(output) else {
    return Err(Strategy(InvalidSelection))
  }
  match native_standard_retained_result(run, output) {
    None =>
      if run.retained_profile is Some(_) {
        Err(Strategy(InvalidSelection))
      } else {
        Ok(output)
      }
    Some(source) =>
      convert_native_retained_result_for_publication(
        output, source, max_rows, values, wire, max_batch_bytes,
      ).map_err(issue => RetainedConversion(task, issue))
  }
}

///|
/// Execute the configured checked Program, persist every declared Named
/// Result, and commit the formal Run publication. Connector selection remains
/// in the portable Host, while all publication progression remains in the
/// portable publication owner. The retained strategy owner stays live until
/// the caller explicitly closes it after downstream use.
pub fn execute_and_publish_native_standard_strategy_run(
  run : NativeStandardStrategyRun,
  service : @native_publication.NativeRunPublicationService,
  context : @native_publication.NativeEffectFreeRunContext,
  results : Array[@native_publication.NativeCapturedResultPublicationContext],
  intent : @native_publication.NativeRunPublicationIntent,
  occurrence : @native_publication.NativeRunPublicationOccurrence,
  export_limits : @publication_host.PublicationOutputExportLimits,
) -> Result[
  @native_publication.NativeRunPublicationResult,
  NativeStandardRunPublicationIssue,
] {
  match execute_native_standard_strategy_run(run) {
    Ok(_) => ()
    Err(issue) => return Err(Strategy(issue))
  }
  let captured = @duckdb_standard_host.dispatch_run(run.dispatch)
  let graph = @strategy.captured_dag_graph(captured)
  let converted : Array[@execution.CompletedOutput?] = []
  for result in 0..<@strategy.graph_result_count(graph) {
    guard @strategy.graph_result_task(graph, result) is Some(task) &&
      @strategy.captured_task_target(captured, task) is Some(target) &&
      @strategy.captured_task_output(captured, task, target) is Some(output) else {
      return Err(Strategy(InvalidSelection))
    }
    match native_standard_retained_result(run, output) {
      None => converted.push(None)
      Some(_) =>
        match
          read_native_standard_task_output(
            run,
            task,
            export_limits.max_rows,
            export_limits.values,
            export_limits.payload_wire,
            export_limits.max_batch_bytes,
          ) {
          Ok(value) => converted.push(Some(value))
          Err(issue) => return Err(issue)
        }
    }
  }
  let prepared = match
    @native_publication.prepare_captured_effect_free_run_publication_native(
      service,
      captured,
      context,
      results,
      intent,
      occurrence,
      export_limits,
      converted_outputs=converted,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  match prepared.commit() {
    Ok(value) => Ok(value)
    Err(issue) => Err(Publication(prepared, issue))
  }
}

///|
pub fn native_standard_strategy_run_complete(
  run : NativeStandardStrategyRun,
) -> Bool {
  run.complete
}

///|
pub fn native_standard_strategy_run_task_count(
  run : NativeStandardStrategyRun,
) -> Int {
  native_strategy_compute_run_task_count(run.runtimes) +
  run.local_owners.length() +
  run.unfiled_local_owners.length()
}

///|
/// Stop new dispatch and release all retained common task owners. A false
/// result or error keeps the owner retryable; it is never inferred as cleanup.
pub fn close_native_standard_strategy_run(
  run : NativeStandardStrategyRun,
) -> Result[Bool, NativeStrategyComputeCleanupIssue] {
  run.accepting = false
  run.stop_dispatch()
  let mut pending = false
  let mut first : NativeStrategyComputeCleanupIssue? = None
  for owner in run.unfiled_local_owners {
    match close_native_strategy_unfiled_local_owner(owner) {
      Ok(_) => ()
      Err(issue) => {
        pending = true
        if first is None {
          first = Some(issue)
        }
      }
    }
  }
  for offset in 0..<run.local_owners.length() {
    let owner = run.local_owners[run.local_owners.length() - offset - 1]
    match close_native_strategy_local_owner(owner) {
      Ok(true) => ()
      Ok(false) => pending = true
      Err(issue) => {
        pending = true
        if first is None {
          first = Some(issue)
        }
      }
    }
  }
  match close_native_strategy_compute_run(run.runtimes) {
    Ok(true) => ()
    Ok(false) => pending = true
    Err(issue) => {
      pending = true
      if first is None {
        first = Some(issue)
      }
    }
  }
  match first {
    Some(issue) => Err(issue)
    None => Ok(!pending)
  }
}
