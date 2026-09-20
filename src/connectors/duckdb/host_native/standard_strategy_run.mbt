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
  execution_bytes : Int64
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
pub fn open_native_standard_strategy_run(
  dispatch : @duckdb_standard_host.StrategyHostDispatch,
  import_limits : NativeComputeImportLimits,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  library? : @native_duckdb.Library? = None,
  database_path? : String = "",
) -> Result[NativeStandardStrategyRun, NativeStandardStrategyRunIssue] {
  if transfer_bytes < 0 || execution_bytes < 0 {
    return Err(InvalidSelection)
  }
  Ok({
    dispatch,
    library,
    runtimes: open_native_strategy_compute_run(),
    import_limits,
    transfer_bytes,
    execution_bytes,
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
/// Execute every checked-ready task through the exact implementation selected
/// by the portable Host. Failure stops admission but leaves task runtimes in
/// this owner until explicit cleanup confirms their release.
pub fn execute_native_standard_strategy_run(
  run : NativeStandardStrategyRun,
) -> Result[Unit, NativeStandardStrategyRunIssue] {
  if !run.accepting {
    return Err(Closed)
  }
  while true {
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
      return Ok(())
    }
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
        Ok(_) => continue
        Err(issue) => {
          run.accepting = false
          run.stop_dispatch()
          return Err(Dispatch(issue))
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
    let database = match library.open_database(path=run.database_path) {
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
        run.execution_bytes,
      ) {
      Ok(_) => ()
      Err(issue) => {
        run.accepting = false
        run.stop_dispatch()
        return Err(DuckDB(issue))
      }
    }
  } nobreak {
    Err(InvalidSelection)
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
