///|
/// The standard strategy runner keeps physical failures separate from common
/// DAG lifecycle failures. Neither category can manufacture the other one's
/// settlement or completion evidence.
pub(all) enum NativeStrategyComputeIssue {
  Physical(NativeComputeExecutionIssue)
  Strategy(@strategy.RunIssue)
  Settlement(@resources.LedgerIssue)
  MissingOutput
}

///|
/// Physical policy for a selected task's independent native file holding.
/// The exact byte reservation is supplied by the configured DuckDB dispatch.
pub(all) struct NativeStrategyRetainedOutputProfile {
  root_path : String
  run_occurrence : String
  max_file_bytes : Int64
  wire : @execution.RowWireLimits
  max_batch_bytes : Int
  max_chunk_rows : Int
}

///|
/// A failed physical release remains distinct from common ledger cleanup.
pub(all) enum NativeStrategyComputeCleanupIssue {
  Ledger(@resources.LedgerIssue)
  FileRelease(@retained_file.NativeRetainedTaskFileIssue)
  LocalCleanup
}

///|
pub(all) struct NativeStrategyComputeFailure {
  primary : NativeStrategyComputeIssue
  rollback : @native_duckdb.NativeDuckDBIssue?
  settlement : @resources.LedgerIssue?
}

///|
/// Standard native ownership of one dispatcher-selected strategy task. The
/// common TaskExecution owns reservation, settlement, publication and cleanup;
/// this runner owns only the physical DuckDB connection and observations.
struct NativeStrategyComputeRuntime {
  graph : @strategy.CapturedDAG
  task_index : Int
  task : @duckdb_driver.CapturedDuckDBTask
  database : @native_duckdb.Database
  transport : @duckdb.TransportColumnLimits
  compute_limits : @duckdb_compute.DuckDBComputeLimits
  imports : Array[NativeComputeImportPlan]
  authority : NativeComputeRuntimeAuthority
  retained_profile : NativeStrategyRetainedOutputProfile?
  retained_bytes : Int64?
  retained_file : Ref[@retained_file.NativeRetainedTaskFile?]
  mut retained_output : @execution.RetainedOutputHandle[
    @retained_file.NativeRetainedTaskFile,
  ]?
  mut output : @execution.CompletedOutput?
  mut started : Bool
  mut physical_active : Bool
  mut database_closed : Bool
  mut task_disposed : Bool
}

///|
fn close_native_strategy_database(
  runtime : NativeStrategyComputeRuntime,
) -> Unit {
  if runtime.database_closed {
    return
  }
  runtime.database.close()
  runtime.database_closed = true
  runtime.physical_active = false
}

///|
fn dispose_native_strategy_task(
  runtime : NativeStrategyComputeRuntime,
) -> @resources.LedgerIssue? {
  let execution = @duckdb_driver.captured_duckdb_execution(runtime.task)
  let settlement = match
    @strategy.settle_task_execution(
      runtime.graph,
      execution,
      !runtime.physical_active,
    ) {
    Ok(_) => None
    Err(issue) => Some(issue)
  }
  if !runtime.task_disposed {
    @strategy.close_task_execution(runtime.graph, execution)
    runtime.task_disposed = true
  }
  settlement
}

///|
/// Preflight uses only the already-selected plan and starts no reservation or
/// I/O. The common task is registered before the transaction can begin.
pub fn start_native_strategy_compute_runtime(
  setup : @duckdb_driver.StrategyComputeHostConfiguration,
  database : @native_duckdb.Database,
  import_limits : NativeComputeImportLimits,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  retained_profile? : NativeStrategyRetainedOutputProfile,
) -> Result[NativeStrategyComputeRuntime, NativeStrategyComputeIssue] {
  let compute = @duckdb_driver.configured_strategy_compute_configuration(setup)
  let transport = @duckdb_driver.configured_compute_transport(compute)
  let compute_limits = @duckdb_driver.configured_compute_limits(compute)
  let plan = match @duckdb_driver.configured_compute_plan(compute) {
    Some(value) => value
    None => {
      database.close()
      return Err(Physical(RuntimeState))
    }
  }
  let imports = match
    native_compute_import_plans(plan, transport, import_limits) {
    Ok(value) => value
    Err(issue) => {
      database.close()
      return Err(Physical(issue))
    }
  }
  let retained_bytes = @duckdb_driver.configured_strategy_output_file_bytes(
    setup,
  )
  match (retained_bytes, retained_profile) {
    (Some(bytes), Some(profile)) if bytes > 0L &&
      bytes == profile.max_file_bytes &&
      profile.root_path != "" &&
      profile.run_occurrence != "" &&
      profile.max_batch_bytes > 0 &&
      profile.max_batch_bytes <= transport.max_bytes &&
      profile.max_chunk_rows > 0 &&
      profile.max_chunk_rows <= transport.max_rows => ()
    (None, None) | (Some(0L), None) => ()
    _ => {
      database.close()
      return Err(Physical(InvalidLimits))
    }
  }
  let retained_file : Ref[@retained_file.NativeRetainedTaskFile?] = Ref(None)
  let retained_storage : (Int64, () -> Bool)? = match retained_bytes {
    Some(bytes) if bytes > 0L =>
      Some(
        (
          bytes,
          fn() {
            match retained_file.val {
              Some(file) => file.release_confirmed()
              None => true
            }
          },
        ),
      )
    _ => None
  }
  let authority : NativeComputeRuntimeAuthority = { settled: None, live: true, }
  let task = match
    @duckdb_driver.start_configured_strategy_compute_host(
      setup,
      current => {
        authority.live &&
        authority.settled is Some(settled) &&
        physical_equal(settled, current)
      },
      transfer_bytes,
      execution_bytes,
      retained_storage?,
    ) {
    Ok(value) => value
    Err(issue) => {
      authority.live = false
      database.close()
      return Err(Strategy(issue))
    }
  }
  let (graph, task_index) = @duckdb_driver.configured_strategy_compute_graph(
    setup,
  )
  Ok({
    graph,
    task_index,
    task,
    database,
    transport,
    compute_limits,
    imports,
    authority,
    retained_profile,
    retained_bytes,
    retained_file,
    retained_output: None,
    output: None,
    started: false,
    physical_active: false,
    database_closed: false,
    task_disposed: false,
  })
}

///|
/// Run the physical transaction, prove native stop, settle the common task,
/// and only then cross the common DAG completion boundary.
pub fn execute_native_strategy_compute_runtime(
  runtime : NativeStrategyComputeRuntime,
  retained_source? : (@execution.ProducerRead) -> NativeComputeRetainedInput?,
) -> Result[@execution.CompletedOutput, NativeStrategyComputeFailure] {
  if runtime.started || runtime.task_disposed {
    return Err({
      primary: Physical(RuntimeState),
      rollback: None,
      settlement: None,
    })
  }
  runtime.started = true
  let retained : NativeComputeRetainedOutput? = match
    (runtime.retained_profile, runtime.retained_bytes) {
    (Some(profile), Some(bytes)) => {
      let file = match
        @retained_file.begin_native_retained_task_file(
          profile.root_path,
          profile.run_occurrence + "-task-" + runtime.task_index.to_string(),
          bytes,
        ) {
        Ok(value) => value
        Err(issue) => {
          close_native_strategy_database(runtime)
          let settlement = dispose_native_strategy_task(runtime)
          return Err({
            primary: Physical(RetainedFile(issue)),
            rollback: None,
            settlement,
          })
        }
      }
      runtime.retained_file.val = Some(file)
      Some({
        file,
        wire: profile.wire,
        max_batch_bytes: profile.max_batch_bytes,
        max_chunk_rows: profile.max_chunk_rows,
      })
    }
    _ => None
  }
  runtime.physical_active = true
  match runtime.database.begin_transaction() {
    Err(issue) => {
      close_native_strategy_database(runtime)
      let settlement = dispose_native_strategy_task(runtime)
      return Err({
        primary: Physical(Runtime(issue)),
        rollback: None,
        settlement,
      })
    }
    Ok(_) => ()
  }
  let mut failure : NativeComputeExecutionIssue? = None
  let attempt = @duckdb_driver.captured_duckdb_attempt(runtime.task)
  for plan in runtime.imports {
    if failure is None {
      match
        execute_native_compute_import(
          runtime.database,
          plan,
          runtime.transport.max_bytes,
          attempt~,
          retained_source?,
        ) {
        Ok(_) => ()
        Err(issue) => failure = Some(issue)
      }
    }
  }
  if failure is None {
    match
      execute_native_compute_query(
        attempt,
        runtime.database,
        runtime.transport,
        runtime.compute_limits,
        retained?,
      ) {
      Ok(output) => runtime.retained_output = output
      Err(issue) => failure = Some(issue)
    }
  }
  if failure is Some(primary) {
    let rollback = match runtime.database.rollback_transaction() {
      Ok(_) => None
      Err(issue) => Some(issue)
    }
    close_native_strategy_database(runtime)
    let settlement = dispose_native_strategy_task(runtime)
    return Err({ primary: Physical(primary), rollback, settlement, })
  }
  match runtime.database.commit_transaction() {
    Err(issue) => {
      let rollback = match runtime.database.rollback_transaction() {
        Ok(_) => None
        Err(cleanup) => Some(cleanup)
      }
      close_native_strategy_database(runtime)
      let settlement = dispose_native_strategy_task(runtime)
      return Err({ primary: Physical(Runtime(issue)), rollback, settlement, })
    }
    Ok(_) => ()
  }
  close_native_strategy_database(runtime)
  runtime.authority.settled = Some(attempt)
  let execution = @duckdb_driver.captured_duckdb_execution(runtime.task)
  match @strategy.settle_task_execution(runtime.graph, execution, true) {
    Err(issue) => {
      let settlement = dispose_native_strategy_task(runtime)
      return Err({ primary: Settlement(issue), rollback: None, settlement, })
    }
    Ok(_) => ()
  }
  match
    @duckdb_driver.complete_captured_duckdb_task(runtime.graph, runtime.task) {
    Err(issue) => {
      let settlement = dispose_native_strategy_task(runtime)
      return Err({ primary: Strategy(issue), rollback: None, settlement, })
    }
    Ok(_) => ()
  }
  let target = @duckdb.fixed_query_target(
    @duckdb.fixed_compute_query(
      @duckdb_compute.duckdb_compute_attempt_plan(attempt),
    ),
  )
  guard @strategy.captured_task_output(
      runtime.graph,
      runtime.task_index,
      target,
    )
    is Some(output) else {
    let settlement = dispose_native_strategy_task(runtime)
    return Err({ primary: MissingOutput, rollback: None, settlement, })
  }
  runtime.output = Some(output)
  Ok(output)
}

///|
pub fn native_strategy_compute_runtime_output(
  runtime : NativeStrategyComputeRuntime,
) -> Result[@execution.CompletedOutput, NativeStrategyComputeIssue] {
  if runtime.task_disposed {
    return Err(Physical(RuntimeState))
  }
  match runtime.output {
    Some(output) => Ok(output)
    None => Err(MissingOutput)
  }
}

///|
/// Close physical and common owners. A failed ledger transition remains
/// retryable through another call and is never converted to confirmed cleanup.
pub fn close_native_strategy_compute_runtime(
  runtime : NativeStrategyComputeRuntime,
) -> Result[Bool, NativeStrategyComputeCleanupIssue] {
  runtime.authority.live = false
  if runtime.retained_file.val is Some(file) {
    file.stop_use()
  }
  close_native_strategy_database(runtime)
  let execution = @duckdb_driver.captured_duckdb_execution(runtime.task)
  match @strategy.settle_task_execution(runtime.graph, execution, true) {
    Err(issue) => return Err(Ledger(issue))
    Ok(_) => ()
  }
  if !runtime.task_disposed {
    @strategy.close_task_execution(runtime.graph, execution)
    runtime.task_disposed = true
  }
  let file_failure = match runtime.retained_file.val {
    Some(file) =>
      match file.reclaim_readers() {
        Err(issue) => Some(issue)
        Ok(_) =>
          match file.release() {
            Ok(_) => None
            Err(issue) => Some(issue)
          }
      }
    None => None
  }
  let common = @strategy.refresh_task_execution_cleanup(
    runtime.graph,
    execution,
  )
  if file_failure is Some(issue) {
    return Err(FileRelease(issue))
  }
  common.map_err(issue => Ledger(issue))
}
