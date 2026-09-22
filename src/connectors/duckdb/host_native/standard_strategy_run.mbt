///|
/// Product owner for one configured Local/DuckDB strategy Run on the native
/// target. The portable configured Host chooses the exact implementation;
/// this owner only connects that choice to synchronous Local execution or a
/// native DuckDB database and retains every common task owner.
struct NativeStandardStrategyRun {
  dispatch : @duckdb_standard_host.StrategyHostDispatch
  library : @native_duckdb.Library?
  runtimes : NativeStrategyComputeRun
  import_limits : NativeComputeImportLimits
  transfer_bytes : Int64
  database_memory_bytes : Int64
  database_path : String
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
}

///|
/// One exact task completed by the configured standard Host. The selected
/// Connector remains private to the Host; remote and publication adapters
/// receive only the checked task index and its admitted output.
pub(all) struct NativeStandardStrategyTaskCompletion {
  task : Int
  output : @execution.CompletedOutput
}

///|
/// Failures from the standard native application boundary. A publication
/// commit failure returns the exact prepared owner so the caller can retry or
/// cancel without re-executing the Program.
pub(all) enum NativeStandardRunPublicationIssue {
  Strategy(NativeStandardStrategyRunIssue)
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
) -> Result[NativeStandardStrategyRun, NativeStandardStrategyRunIssue] {
  if transfer_bytes < 0 || execution_bytes <= 0 {
    return Err(InvalidSelection)
  }
  Ok({
    dispatch,
    library,
    runtimes: open_native_strategy_compute_run(),
    import_limits,
    transfer_bytes,
    database_memory_bytes: execution_bytes,
    database_path,
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
    match @duckdb_standard_host.execute_synchronous_dispatch(task) {
      Err(issue) => {
        run.accepting = false
        run.stop_dispatch()
        return Err(Dispatch(issue))
      }
      Ok(_) => {
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
        return Ok(Some({ task: task_index, output, }))
      }
    }
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
    ) {
    Ok(output) => Ok(Some({ task: task_index, output, }))
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
  let prepared = match
    @native_publication.prepare_captured_effect_free_run_publication_native(
      service, captured, context, results, intent, occurrence, export_limits,
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
  native_strategy_compute_run_task_count(run.runtimes)
}

///|
/// Stop new dispatch and release all retained common task owners. A false
/// result or error keeps the owner retryable; it is never inferred as cleanup.
pub fn close_native_standard_strategy_run(
  run : NativeStandardStrategyRun,
) -> Result[Bool, @resources.LedgerIssue] {
  run.accepting = false
  run.stop_dispatch()
  close_native_strategy_compute_run(run.runtimes)
}
