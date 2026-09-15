///|
struct ComputeNodeRun {
  attempt : @duckdb_compute.DuckDBComputeAttempt
  transport : @duckdb.TransportColumnLimits
  strategy : (@strategy.CapturedDAG, Int, @duckdb_driver.CapturedDuckDBTask)?
  mut closed : Bool
}

///|
#export_name("computeStrategyRetentionCapacity")
pub fn compute_strategy_retention_capacity(
  setup : @host.StrategyComputeHostConfiguration,
) -> Int64 raise NodeHostFailure {
  guard @host.configured_strategy_retention_capacity(setup) is Some(bytes) else {
    raise Physical(InvalidLimits)
  }
  bytes
}

///|
#export_name("computeStrategyScratchCapacity")
pub fn compute_strategy_scratch_capacity(
  setup : @host.StrategyComputeHostConfiguration,
) -> Int64 raise NodeHostFailure {
  guard @host.configured_strategy_scratch_capacity(setup) is Some(bytes) else {
    raise Physical(InvalidLimits)
  }
  bytes
}

///|
#export_name("computeHostOpen")
pub fn compute_host_open(
  setup : @host.ComputeHostConfiguration,
  verify : (@duckdb_compute.DuckDBComputeAttempt) -> Bool,
) -> ComputeNodeRun raise NodeHostFailure {
  match @host.start_configured_compute_host(setup, verify) {
    Ok(attempt) =>
      {
        attempt,
        transport: @host.configured_compute_transport(setup),
        strategy: None,
        closed: false,
      }
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeStrategyHostOpen")
pub fn compute_strategy_host_open(
  setup : @host.StrategyComputeHostConfiguration,
  verify : (@duckdb_compute.DuckDBComputeAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
) -> ComputeNodeRun raise NodeHostFailure {
  open_strategy_compute_host(setup, verify, transfer_bytes, execution_bytes)
}

///|
#export_name("computeResidentStrategyHostOpen")
pub fn compute_resident_strategy_host_open(
  setup : @host.StrategyComputeHostConfiguration,
  verify : (@duckdb_compute.DuckDBComputeAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  resident : @strategy.ResidentInputs,
) -> ComputeNodeRun raise NodeHostFailure {
  open_strategy_compute_host(
    setup,
    verify,
    transfer_bytes,
    execution_bytes,
    resident~,
  )
}

///|
fn open_strategy_compute_host(
  setup : @host.StrategyComputeHostConfiguration,
  verify : (@duckdb_compute.DuckDBComputeAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  resident? : @strategy.ResidentInputs,
) -> ComputeNodeRun raise NodeHostFailure {
  match
    @host.start_configured_strategy_compute_host(
      setup,
      verify,
      transfer_bytes,
      execution_bytes,
      resident?,
    ) {
    Ok(task_handle) =>
      {
        attempt: @duckdb_driver.captured_duckdb_attempt(task_handle),
        transport: @host.configured_strategy_compute_transport(setup),
        strategy: Some(
          (
            @host.configured_strategy_compute_graph(setup).0,
            @host.configured_strategy_compute_graph(setup).1,
            task_handle,
          ),
        ),
        closed: false,
      }
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("computeResidentSql")
pub fn compute_resident_sql(
  run : ComputeNodeRun,
  kind : Int,
) -> String raise NodeHostFailure {
  guard run.strategy is Some((graph, _, task_handle)) &&
    @duckdb_driver.captured_duckdb_query(graph, task_handle) is Some(query) else {
    raise InvalidCommand
  }
  match kind {
    0 => @duckdb.resident_query_create_sql(query)
    1 => @duckdb.resident_query_read_sql(query)
    2 => @duckdb.resident_query_drop_sql(query)
    _ => raise InvalidCommand
  }
}

///|
#export_name("computeResidentCommit")
pub fn compute_resident_commit(
  run : ComputeNodeRun,
) -> Unit raise NodeHostFailure {
  guard run.strategy is Some((graph, _, task_handle)) else {
    raise InvalidCommand
  }
  match
    @strategy.confirm_captured_resident_output(
      graph,
      @duckdb_driver.captured_duckdb_execution(task_handle),
    ) {
    Ok(_) => ()
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("computeResidentCleanupSql")
pub fn compute_resident_cleanup_sql(
  run : ComputeNodeRun,
) -> Array[String] raise NodeHostFailure {
  guard run.strategy is Some((graph, _, task_handle)) else {
    raise InvalidCommand
  }
  match @duckdb_driver.captured_duckdb_cleanup_sql(graph, task_handle) {
    Ok(value) => value
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("computeHostPhysicalCharge")
pub fn compute_host_physical_charge(
  run : ComputeNodeRun,
  bytes : Int64,
) -> Unit raise NodeHostFailure {
  if run.strategy is Some((graph, _, task_handle)) {
    match
      @strategy.charge_task_execution_transfer(
        graph,
        @duckdb_driver.captured_duckdb_execution(task_handle),
        bytes,
      ) {
      Ok(_) => ()
      Err(issue) => raise Physical(issue)
    }
  }
}

///|
#export_name("computeHostPhysicalSettle")
pub fn compute_host_physical_settle(
  run : ComputeNodeRun,
  confirmed : Bool,
) -> Unit raise NodeHostFailure {
  if run.strategy is Some((graph, _, task_handle)) {
    match
      @strategy.settle_task_execution(
        graph,
        @duckdb_driver.captured_duckdb_execution(task_handle),
        confirmed,
      ) {
      Ok(_) => ()
      Err(issue) => raise Physical(issue)
    }
  }
}

///|
#export_name("computeHostAttempt")
pub fn compute_host_attempt(
  run : ComputeNodeRun,
) -> @duckdb_compute.DuckDBComputeAttempt {
  run.attempt
}

///|
#export_name("computeHostCount")
pub fn compute_host_count(
  run : ComputeNodeRun,
  port : Int,
  columns : Bool,
) -> Int raise NodeHostFailure {
  guard @duckdb.fixed_compute_import(
      @duckdb_compute.duckdb_compute_attempt_plan(run.attempt),
      port,
    )
    is Some(imported) else {
    raise InvalidCommand
  }
  if columns {
    @duckdb.fixed_import_column_count(imported)
  } else {
    @execution.producer_read_row_count(@duckdb.fixed_import_input(imported))
  }
}

///|
#export_name("computeHostImportCount")
pub fn compute_host_import_count(run : ComputeNodeRun) -> Int {
  @duckdb.fixed_compute_import_count(
    @duckdb_compute.duckdb_compute_attempt_plan(run.attempt),
  )
}

///|
#export_name("computeHostSql")
pub fn compute_host_sql(
  run : ComputeNodeRun,
  kind : Int,
  port : Int,
) -> String raise NodeHostFailure {
  let compute = @duckdb_compute.duckdb_compute_attempt_plan(run.attempt)
  guard @duckdb.fixed_compute_import(compute, port) is Some(imported) else {
    raise InvalidCommand
  }
  match kind {
    0 => @duckdb.fixed_import_create_sql(imported)
    1 => @duckdb.fixed_import_insert_sql(imported)
    2 => @duckdb.fixed_query_sql(@duckdb.fixed_compute_query(compute))
    _ => raise InvalidCommand
  }
}

///|
#export_name("computeHostParameter")
pub fn compute_host_parameter(
  run : ComputeNodeRun,
  row : Int,
  column : Int,
  predicate : Bool,
  port : Int,
) -> String raise NodeHostFailure {
  let compute = @duckdb_compute.duckdb_compute_attempt_plan(run.attempt)
  let parameter = if predicate {
    guard @duckdb.fixed_query_parameter(
        @duckdb.fixed_compute_query(compute),
        column,
      )
      is Some(parameter) else {
      raise InvalidCommand
    }
    parameter
  } else {
    guard @duckdb.fixed_compute_import(compute, port) is Some(imported) else {
      raise InvalidCommand
    }
    match @duckdb.fixed_import_parameter(imported, row, column) {
      Ok(value) => value
      Err(issue) => raise ComputeParameter(issue)
    }
  }
  try {
    let writer = @encode.writer(
      run.transport.max_bytes,
      run.transport.max_nodes,
      4,
    )
    @duckdb.emit_physical_parameter(parameter, writer)
    @encode.finish(writer)
  } catch {
    issue => raise Encoding(issue)
  }
}

///|
#export_name("computeHostBegin")
pub fn compute_host_begin(
  run : ComputeNodeRun,
  fields : String,
) -> Unit raise NodeHostFailure {
  match
    @duckdb_compute.begin_duckdb_compute_result(
      run.attempt,
      transport_fields(run.transport, fields),
    ) {
    Ok(_) => ()
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostAccept")
pub fn compute_host_accept(
  run : ComputeNodeRun,
  rows : Int,
  data : String,
) -> Unit raise NodeHostFailure {
  match
    @duckdb_compute.receive_duckdb_compute_chunk(
      run.attempt,
      rows,
      chunk_columns(run.transport, data),
    ) {
    Ok(_) => ()
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostFinish")
pub fn compute_host_finish(run : ComputeNodeRun) -> Unit raise NodeHostFailure {
  match @duckdb_compute.finish_duckdb_compute_result(run.attempt) {
    Ok(_) => ()
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostComplete")
pub fn compute_host_complete(
  run : ComputeNodeRun,
) -> @execution.CompletedOutput raise NodeHostFailure {
  if run.strategy is Some((graph, task, task_handle)) {
    match
      @strategy.complete_task_execution(
        graph,
        @duckdb_driver.captured_duckdb_execution(task_handle),
      ) {
      Err(issue) => raise Strategy(issue)
      Ok(_) => ()
    }
    let target = @duckdb.fixed_query_target(
      @duckdb.fixed_compute_query(
        @duckdb_compute.duckdb_compute_attempt_plan(run.attempt),
      ),
    )
    guard @strategy.captured_task_output(graph, task, target) is Some(output) else {
      raise InvalidCommand
    }
    return output
  }
  match @duckdb_compute.complete_duckdb_compute_attempt(run.attempt) {
    Ok(value) => value
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostQueryParameterCount")
pub fn compute_host_query_parameter_count(run : ComputeNodeRun) -> Int {
  @duckdb.fixed_query_parameter_count(
    @duckdb.fixed_compute_query(
      @duckdb_compute.duckdb_compute_attempt_plan(run.attempt),
    ),
  )
}

///|
#export_name("computeHostAbort")
pub fn compute_host_abort(run : ComputeNodeRun) -> Unit {
  if run.strategy is Some((graph, _, _)) {
    @strategy.stop_captured_dag(graph)
  }
  @duckdb_compute.abort_duckdb_compute_attempt(run.attempt)
}

///|
#export_name("computeHostClose")
pub fn compute_host_close(run : ComputeNodeRun) -> Unit {
  if run.closed {
    return
  }
  run.closed = true
  @duckdb_compute.close_duckdb_compute_attempt(run.attempt)
  if run.strategy is Some((graph, _, task_handle)) {
    @strategy.close_task_execution(
      graph,
      @duckdb_driver.captured_duckdb_execution(task_handle),
    )
  }
}
