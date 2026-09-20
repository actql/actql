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
) -> Result[@execution.CompletedOutput, NativeStrategyComputeFailure] {
  if runtime.started || runtime.task_disposed {
    return Err({
      primary: Physical(RuntimeState),
      rollback: None,
      settlement: None,
    })
  }
  runtime.started = true
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
  for plan in runtime.imports {
    if failure is None {
      match
        execute_native_compute_import(
          runtime.database,
          plan,
          runtime.transport.max_bytes,
        ) {
        Ok(_) => ()
        Err(issue) => failure = Some(issue)
      }
    }
  }
  let attempt = @duckdb_driver.captured_duckdb_attempt(runtime.task)
  if failure is None {
    match
      execute_native_compute_query(
        attempt,
        runtime.database,
        runtime.transport,
        runtime.compute_limits,
      ) {
      Ok(_) => ()
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
  match @strategy.complete_task_execution(runtime.graph, execution) {
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
) -> Result[Bool, @resources.LedgerIssue] {
  runtime.authority.live = false
  close_native_strategy_database(runtime)
  let execution = @duckdb_driver.captured_duckdb_execution(runtime.task)
  match @strategy.settle_task_execution(runtime.graph, execution, true) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !runtime.task_disposed {
    @strategy.close_task_execution(runtime.graph, execution)
    runtime.task_disposed = true
  }
  @strategy.refresh_task_execution_cleanup(runtime.graph, execution)
}
