///|
priv struct NativePhysical {
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  retention : Int64
  scratch : Int64
  mut settled : Bool
  mut closed : Bool
  mut completed : Bool
  mut holding : @resources.Holding?
  mut dag : @strategy.CapturedDAG?
  mut source : @query.CapturedInputSource?
  mut observation : @duckdb_query.DuckDBNativeObservation?
}

///|
#export_name("nativeHostCapacity")
pub fn native_host_capacity(
  setup : @host.NativeHostConfiguration,
  retained : Bool,
) -> Int64 raise NodeHostFailure {
  guard @host.configured_native_capacity(setup) is Some(capacity) else {
    raise Physical(InvalidLimits)
  }
  if retained {
    capacity.retained_bytes
  } else {
    capacity.execution_bytes
  }
}

///|
#export_name("nativeStrategyHostOpen")
pub fn native_strategy_host_open(
  setup : @host.NativeHostConfiguration,
  ledger : @resources.Ledger,
  nonce : String,
  verify : (@duckdb_query.DuckDBNativeAttempt) -> Bool,
  transfer : Int64,
  execution : Int64,
) -> NativeNodeRun raise NodeHostFailure {
  guard @host.configured_native_capacity(setup) is Some(capacity) else {
    raise Physical(InvalidLimits)
  }
  if execution < 0L ||
    execution > 9223372036854775807L - capacity.execution_bytes {
    raise Physical(InvalidLimits)
  }
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      transfer,
      capacity.retained_bytes,
      execution + capacity.execution_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise Physical(issue)
  }
  match @host.start_configured_native_host(setup, nonce, verify) {
    Err(issue) => {
      @resources.settle_reservation(ledger, reservation) |> ignore
      raise Host(issue)
    }
    Ok(host) =>
      {
        host,
        limits: @host.configured_native_host_limits(setup),
        physical: Some({
          ledger,
          reservation,
          retention: capacity.retained_bytes,
          scratch: capacity.execution_bytes,
          settled: false,
          closed: false,
          completed: false,
          holding: None,
          dag: None,
          source: None,
          observation: None,
        }),
      }
  }
}

///|
#export_name("nativeHostPhysicalCharge")
pub fn native_host_physical_charge(
  run : NativeNodeRun,
  bytes : Int64,
) -> Unit raise NodeHostFailure {
  guard run.physical is Some(p) && !p.closed else {
    raise Physical(InvalidCharge)
  }
  match @resources.charge_transfer(p.ledger, p.reservation, bytes) {
    Ok(_) => ()
    Err(issue) => raise Physical(issue)
  }
}

///|
#export_name("nativeHostPhysicalSettle")
pub fn native_host_physical_settle(
  run : NativeNodeRun,
  confirmed : Bool,
) -> Unit raise NodeHostFailure {
  guard run.physical is Some(p) else { raise Physical(InvalidCharge) }
  if p.settled {
    return
  }
  let result = if !confirmed {
    @resources.mark_cleanup_pending(p.ledger, p.reservation)
  } else if p.closed {
    @resources.settle_reservation(p.ledger, p.reservation)
  } else {
    @resources.settle_execution_reservation(
      p.ledger,
      p.reservation,
      remaining_execution=p.scratch,
    )
  }
  match result {
    Ok(_) => if confirmed { p.settled = true }
    Err(issue) => raise Physical(issue)
  }
}

///|
#export_name("nativeHostOpenDAG")
pub fn native_host_open_dag(
  run : NativeNodeRun,
  graph : @strategy.CheckedDAG,
  observation : @duckdb_query.DuckDBNativeObservation,
) -> @strategy.CapturedDAG raise NodeHostFailure {
  guard run.physical is Some(p) &&
    !p.closed &&
    p.completed &&
    p.dag is None &&
    p.holding is Some(holding) else {
    raise Physical(InvalidCharge)
  }
  guard p.source is Some(source) &&
    p.observation is Some(expected) &&
    physical_equal(expected, observation) else {
    raise Physical(InvalidCharge)
  }
  let dag = match @strategy.open_captured_dag(graph, source, p.ledger) {
    Ok(value) => value
    Err(issue) => raise Strategy(issue)
  }
  match @strategy.retain_captured_task_allocation(dag, 0, holding) {
    Ok(_) => {
      p.dag = Some(dag)
      p.holding = None
      p.source = None
      dag
    }
    Err(issue) => raise Physical(issue)
  }
}

///|
fn close_native_physical(run : NativeNodeRun) -> Unit {
  guard run.physical is Some(p) && !p.closed else { return }
  p.closed = true
  p.source = None
  p.observation = None
  if p.dag is Some(dag) {
    @strategy.close_captured_task_output(dag, 0)
  }
  if p.holding is Some(holding) {
    @resources.release_allocation(p.ledger, holding) |> ignore
    p.holding = None
  }
  if p.settled && !p.completed {
    @resources.settle_reservation(p.ledger, p.reservation) |> ignore
  }
}
