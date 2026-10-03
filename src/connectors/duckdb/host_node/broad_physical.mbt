///|
priv struct BroadPhysical {
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  capacity : @acquisition_host.NativeCapacity
  release_confirmed : () -> Bool
  mut settled : Bool
  mut closed : Bool
  mut holding : @resources.Holding?
  mut capture : @acquisition_host.BroadHostSourceCapture?
  mut source : @query.CapturedInputSource?
  mut observation : @duckdb_query.DuckDBBroadObservation?
  mut dag : (@strategy.CapturedDAG, Int)?
}

///|
#export_name("broadHostCapacity")
pub fn broad_host_capacity(
  setup : @acquisition_host.BroadHostConfiguration,
  retained : Bool,
) -> Int64 raise NodeHostFailure {
  guard @acquisition_host.configured_broad_capacity(setup) is Some(capacity) else {
    raise Physical(InvalidLimits)
  }
  if retained {
    capacity.retained_bytes
  } else {
    capacity.execution_bytes
  }
}

///|
/// Reserve before any physical read; use the original selected configuration
/// and bounded Client/Local residual, with no synthetic Native preparation.
#export_name("broadStrategyHostOpen")
pub fn broad_strategy_host_open(
  setup : @acquisition_host.BroadHostConfiguration,
  ledger : @resources.Ledger,
  nonce : String,
  verify : (@duckdb_query.DuckDBBroadAttempt) -> Bool,
  transfer : Int64,
  execution : Int64,
  release_confirmed : () -> Bool,
) -> BroadNodeRun raise NodeHostFailure {
  guard @acquisition_host.configured_broad_capacity(setup) is Some(capacity) &&
    execution >= 0L &&
    execution <= 9223372036854775807L - capacity.execution_bytes else {
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
  match @acquisition_host.start_configured_broad_host(setup, nonce, verify) {
    Err(issue) => {
      @resources.settle_reservation(ledger, reservation) |> ignore
      raise Broad(issue)
    }
    Ok(host) =>
      {
        host,
        limits: @acquisition_host.configured_broad_host_limits(setup),
        physical: Some({
          ledger,
          reservation,
          capacity,
          release_confirmed,
          settled: false,
          closed: false,
          holding: None,
          capture: None,
          source: None,
          observation: None,
          dag: None,
        }),
      }
  }
}

///|
#export_name("broadHostPhysicalCharge")
pub fn broad_host_physical_charge(
  run : BroadNodeRun,
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
#export_name("broadHostPhysicalSettle")
pub fn broad_host_physical_settle(
  run : BroadNodeRun,
  confirmed : Bool,
) -> Unit raise NodeHostFailure {
  guard run.physical is Some(p) else { raise Physical(InvalidCharge) }
  if p.settled {
    return
  }
  let result = if confirmed {
    @resources.settle_execution_reservation(
      p.ledger,
      p.reservation,
      remaining_execution=if p.closed { 0L } else { p.capacity.execution_bytes },
    )
  } else {
    @resources.mark_cleanup_pending(p.ledger, p.reservation)
  }
  match result {
    Ok(_) =>
      if confirmed {
        p.settled = true
        refresh_broad_physical(run)
      }
    Err(issue) => raise Physical(issue)
  }
}

///|
/// Adopt only the original issuer's completed observation, after the bounded
/// residual returns. Reservation remains live through verification and capture.
#export_name("broadHostPhysicalComplete")
pub fn broad_host_physical_complete(
  run : BroadNodeRun,
  observation : @duckdb_query.DuckDBBroadObservation,
) -> Unit raise NodeHostFailure {
  guard run.physical is Some(p) else { return }
  if p.closed || !p.settled || p.holding is Some(_) || p.observation is Some(_) {
    raise Physical(InvalidCharge)
  }
  let capture = broad_host_source_capture(run, observation)
  let source = broad_host_source_capture_source(capture)
  let holding = match
    @resources.retain_allocation(
      p.ledger,
      p.reservation,
      p.capacity.retained_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise Physical(issue)
  }
  p.holding = Some(holding)
  p.capture = Some(capture)
  p.source = Some(source)
  p.observation = Some(observation)
  match @resources.settle_reservation(p.ledger, p.reservation) {
    Ok(_) => ()
    Err(issue) => raise Physical(issue)
  }
}

///|
#export_name("broadHostRetainCapturedTask")
pub fn broad_host_retain_captured_task(
  run : BroadNodeRun,
  dag : @strategy.CapturedDAG,
  task : Int,
  observation : @duckdb_query.DuckDBBroadObservation,
) -> Unit raise NodeHostFailure {
  guard run.physical is Some(p) &&
    !p.closed &&
    p.dag is None &&
    p.holding is Some(holding) &&
    p.source is Some(source) &&
    p.observation is Some(expected) &&
    physical_equal(expected, observation) &&
    physical_equal(p.ledger, @strategy.captured_dag_ledger(dag)) &&
    @strategy.captured_task_source_matches(dag, task, source) else {
    raise Physical(InvalidCharge)
  }
  match
    @strategy.retain_captured_task_allocation(dag, task, holding, release_confirmed=fn() {
      p.closed && (p.release_confirmed)()
    }) {
    Ok(_) => {
      p.dag = Some((dag, task))
      p.holding = None
    }
    Err(issue) => raise Physical(issue)
  }
}

///|
fn close_broad_physical(run : BroadNodeRun) -> Unit {
  guard run.physical is Some(p) else { return }
  if !p.closed {
    p.closed = true
    p.capture = None
    p.source = None
    p.observation = None
    if p.dag is Some((dag, task)) {
      @strategy.close_captured_task_output(dag, task)
    }
  }
  refresh_broad_physical(run)
}

///|
fn refresh_broad_physical(run : BroadNodeRun) -> Unit {
  guard run.physical is Some(p) && p.closed else { return }
  if p.dag is Some((dag, _)) {
    @strategy.refresh_captured_retention(dag)
  }
  if !p.settled || !(p.release_confirmed)() {
    if @resources.reservation_open(p.reservation) {
      @resources.mark_cleanup_pending(p.ledger, p.reservation) |> ignore
    }
    return
  }
  if p.holding is Some(holding) {
    @resources.release_allocation(p.ledger, holding) |> ignore
    p.holding = None
  }
  if @resources.reservation_open(p.reservation) {
    @resources.settle_reservation(p.ledger, p.reservation) |> ignore
  }
}

///|
#export_name("broadHostPhysicalRefresh")
pub fn broad_host_physical_refresh(run : BroadNodeRun) -> Unit {
  refresh_broad_physical(run)
}
