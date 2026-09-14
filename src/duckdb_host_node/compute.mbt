///|
struct ComputeNodeRun {
  attempt : @planning.DuckDBComputeAttempt
  transport : @duckdb.TransportColumnLimits
  strategy : (@strategy.CapturedDAG, Int)?
}

///|
#export_name("computeHostOpen")
pub fn compute_host_open(
  setup : @host.ComputeHostConfiguration,
  verify : (@planning.DuckDBComputeAttempt) -> Bool,
) -> ComputeNodeRun raise NodeHostFailure {
  match @host.start_configured_compute_host(setup, verify) {
    Ok(attempt) =>
      {
        attempt,
        transport: @host.configured_compute_transport(setup),
        strategy: None,
      }
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeStrategyHostOpen")
pub fn compute_strategy_host_open(
  setup : @host.StrategyComputeHostConfiguration,
  verify : (@planning.DuckDBComputeAttempt) -> Bool,
) -> ComputeNodeRun raise NodeHostFailure {
  match @host.start_configured_strategy_compute_host(setup, verify) {
    Ok(attempt) =>
      {
        attempt,
        transport: @host.configured_strategy_compute_transport(setup),
        strategy: Some(@host.configured_strategy_compute_graph(setup)),
      }
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("computeHostAttempt")
pub fn compute_host_attempt(
  run : ComputeNodeRun,
) -> @planning.DuckDBComputeAttempt {
  run.attempt
}

///|
#export_name("computeHostCount")
pub fn compute_host_count(run : ComputeNodeRun, columns : Bool) -> Int {
  let imported = @duckdb.fixed_compute_import(
    @planning.duckdb_compute_attempt_plan(run.attempt),
  )
  if columns {
    @duckdb.fixed_import_column_count(imported)
  } else {
    @execution.producer_read_row_count(@duckdb.fixed_import_input(imported))
  }
}

///|
#export_name("computeHostSql")
pub fn compute_host_sql(
  run : ComputeNodeRun,
  kind : Int,
) -> String raise NodeHostFailure {
  let compute = @planning.duckdb_compute_attempt_plan(run.attempt)
  match kind {
    0 => @duckdb.fixed_import_create_sql(@duckdb.fixed_compute_import(compute))
    1 => @duckdb.fixed_import_insert_sql(@duckdb.fixed_compute_import(compute))
    2 => @duckdb.native_query_sql(@duckdb.fixed_compute_query(compute))
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
) -> String raise NodeHostFailure {
  let compute = @planning.duckdb_compute_attempt_plan(run.attempt)
  let parameter = if predicate {
    @duckdb.native_query_parameter(@duckdb.fixed_compute_query(compute))
  } else {
    match
      @duckdb.fixed_import_parameter(
        @duckdb.fixed_compute_import(compute),
        row,
        column,
      ) {
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
    @planning.begin_duckdb_compute_result(
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
    @planning.receive_duckdb_compute_chunk(
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
  match @planning.finish_duckdb_compute_result(run.attempt) {
    Ok(_) => ()
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostComplete")
pub fn compute_host_complete(
  run : ComputeNodeRun,
) -> @execution.CompletedOutput raise NodeHostFailure {
  if run.strategy is Some((graph, task)) {
    match @strategy.complete_captured_duckdb_task(graph, run.attempt) {
      Err(issue) => raise Strategy(issue)
      Ok(_) => ()
    }
    guard @strategy.captured_task_output(graph, task, Step(1)) is Some(output) else {
      raise InvalidCommand
    }
    return output
  }
  match @planning.complete_duckdb_compute_attempt(run.attempt) {
    Ok(value) => value
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostAbort")
pub fn compute_host_abort(run : ComputeNodeRun) -> Unit {
  if run.strategy is Some((graph, _)) {
    @strategy.stop_captured_dag(graph)
  }
  @planning.abort_duckdb_compute_attempt(run.attempt)
}

///|
#export_name("computeHostClose")
pub fn compute_host_close(run : ComputeNodeRun) -> Unit {
  @planning.close_duckdb_compute_attempt(run.attempt)
}
