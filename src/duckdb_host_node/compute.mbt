///|
struct ComputeNodeRun {
  attempt : @planning.DuckDBComputeAttempt
  transport : @duckdb.TransportColumnLimits
  strategy : (@strategy.CapturedDAG, Int)?
  physical : (@strategy.Ledger, @strategy.Reservation)?
  mut physical_settled : Bool
  retention_bytes : Int64
  scratch_bytes : Int64
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
  verify : (@planning.DuckDBComputeAttempt) -> Bool,
) -> ComputeNodeRun raise NodeHostFailure {
  match @host.start_configured_compute_host(setup, verify) {
    Ok(attempt) =>
      {
        attempt,
        transport: @host.configured_compute_transport(setup),
        strategy: None,
        physical: None,
        physical_settled: false,
        retention_bytes: 0L,
        scratch_bytes: 0L,
        closed: false,
      }
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeStrategyHostOpen")
pub fn compute_strategy_host_open(
  setup : @host.StrategyComputeHostConfiguration,
  verify : (@planning.DuckDBComputeAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
) -> ComputeNodeRun raise NodeHostFailure {
  let ledger = @host.configured_strategy_compute_ledger(setup)
  let (graph, task) = @host.configured_strategy_compute_graph(setup)
  guard @host.configured_strategy_retention_capacity(setup)
    is Some(retention_bytes) else {
    raise Physical(InvalidLimits)
  }
  guard @host.configured_strategy_scratch_capacity(setup) is Some(scratch_bytes) else {
    raise Physical(InvalidLimits)
  }
  if execution_bytes < 0L ||
    execution_bytes > 9223372036854775807L - scratch_bytes {
    raise Physical(InvalidLimits)
  }
  let execution_bytes = execution_bytes + scratch_bytes
  if @strategy.strategy_task_envelope(graph, task) is Some(capacity) &&
    (
      transfer_bytes > capacity.transfer_bytes ||
      execution_bytes > capacity.execution_bytes ||
      retention_bytes > capacity.retained_bytes
    ) {
    raise Physical(InvalidCharge)
  }
  let reservation = match
    @strategy.reserve_attempt(
      ledger, transfer_bytes, retention_bytes, execution_bytes,
    ) {
    Ok(reservation) => reservation
    Err(issue) => raise Physical(issue)
  }
  match @host.start_configured_strategy_compute_host(setup, verify) {
    Ok(attempt) =>
      {
        attempt,
        transport: @host.configured_strategy_compute_transport(setup),
        strategy: Some(@host.configured_strategy_compute_graph(setup)),
        physical: Some((ledger, reservation)),
        physical_settled: false,
        retention_bytes,
        scratch_bytes,
        closed: false,
      }
    Err(issue) => {
      @strategy.settle_reservation(ledger, reservation) |> ignore
      raise Strategy(issue)
    }
  }
}

///|
#export_name("computeHostPhysicalCharge")
pub fn compute_host_physical_charge(
  run : ComputeNodeRun,
  bytes : Int64,
) -> Unit raise NodeHostFailure {
  if run.physical is Some((ledger, reservation)) {
    match @strategy.charge_transfer(ledger, reservation, bytes) {
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
  if run.physical_settled {
    return
  }
  if run.physical is Some((ledger, reservation)) {
    let result = if confirmed {
      if run.closed {
        @strategy.settle_reservation(ledger, reservation)
      } else {
        @strategy.settle_execution_reservation(
          ledger,
          reservation,
          remaining_execution=run.scratch_bytes,
        )
      }
    } else {
      @strategy.mark_cleanup_pending(ledger, reservation)
    }
    match result {
      Ok(_) => if confirmed { run.physical_settled = true }
      Err(issue) => raise Physical(issue)
    }
    if confirmed && run.strategy is Some((graph, _)) {
      @strategy.captured_cleanup_confirmed(graph, run.attempt)
    }
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
    if !run.physical_settled {
      raise InvalidCommand
    }
    guard run.physical is Some((ledger, reservation)) else {
      raise InvalidCommand
    }
    let holding = match
      @strategy.retain_allocation(ledger, reservation, run.retention_bytes) {
      Ok(holding) => holding
      Err(issue) => raise Physical(issue)
    }
    match @strategy.complete_captured_duckdb_task(graph, run.attempt) {
      Err(issue) => {
        @strategy.release_allocation(ledger, holding) |> ignore
        raise Strategy(issue)
      }
      Ok(_) => ()
    }
    match @strategy.retain_captured_task_allocation(graph, task, holding) {
      Err(issue) => {
        @strategy.release_allocation(ledger, holding) |> ignore
        @strategy.close_captured_task_output(graph, task)
        raise Physical(issue)
      }
      Ok(_) => ()
    }
    @strategy.settle_reservation(ledger, reservation) |> ignore
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
  if run.closed {
    return
  }
  run.closed = true
  @planning.close_duckdb_compute_attempt(run.attempt)
  if run.strategy is Some((graph, task)) {
    @strategy.close_captured_task_output(graph, task)
    if run.physical_settled {
      if run.physical is Some((ledger, reservation)) {
        @strategy.settle_reservation(ledger, reservation) |> ignore
      }
      @strategy.captured_cleanup_confirmed(graph, run.attempt)
    }
  }
}
