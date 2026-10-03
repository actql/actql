///|
priv struct NativePhysical {
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  retention : Int64
  file_capacity : Int64
  mut sealed_file_bytes : Int64?
  scratch : Int64
  release_confirmed : () -> Bool
  mut settled : Bool
  mut closed : Bool
  mut completed : Bool
  mut holding : @resources.Holding?
  mut dag : (@strategy.CapturedDAG, Int)?
  mut capture : @acquisition_host.NativeHostSourceCapture?
  mut source : @query.CapturedInputSource?
  mut observation : @duckdb_query.DuckDBNativeObservation?
}

///|
#export_name("nativeHostCapacity")
pub fn native_host_capacity(
  setup : @acquisition_host.NativeHostConfiguration,
  retained : Bool,
) -> Int64 raise NodeHostFailure {
  guard @acquisition_host.configured_native_capacity(setup) is Some(capacity) else {
    raise Physical(InvalidLimits)
  }
  if retained {
    capacity.retained_bytes
  } else {
    capacity.execution_bytes
  }
}

///|
#export_name("nativeRetainedHostCapacity")
pub fn native_retained_host_capacity(
  setup : @acquisition_host.NativeHostConfiguration,
  retained : Bool,
) -> Int64 raise NodeHostFailure {
  guard @acquisition_host.configured_retained_native_capacity(setup)
    is Some(capacity) else {
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
  setup : @acquisition_host.NativeHostConfiguration,
  ledger : @resources.Ledger,
  nonce : String,
  verify : (@duckdb_query.DuckDBNativeAttempt) -> Bool,
  transfer : Int64,
  execution : Int64,
) -> NativeNodeRun raise NodeHostFailure {
  open_native_physical(setup, ledger, nonce, verify, transfer, execution, 0L, fn() {
    true
  })
}

///|
#export_name("nativeRetainedStrategyHostOpen")
pub fn native_retained_strategy_host_open(
  setup : @acquisition_host.NativeHostConfiguration,
  ledger : @resources.Ledger,
  nonce : String,
  verify : (@duckdb_query.DuckDBNativeAttempt) -> Bool,
  transfer : Int64,
  execution : Int64,
  file_bytes : Int64,
  max_batch_bytes : Int,
  release_confirmed : () -> Bool,
) -> NativeNodeRun raise NodeHostFailure {
  open_native_physical(
    setup,
    ledger,
    nonce,
    verify,
    transfer,
    execution,
    file_bytes,
    release_confirmed,
    stream_batch=Some(max_batch_bytes),
  )
}

///|
fn open_native_physical(
  setup : @acquisition_host.NativeHostConfiguration,
  ledger : @resources.Ledger,
  nonce : String,
  verify : (@duckdb_query.DuckDBNativeAttempt) -> Bool,
  transfer : Int64,
  execution : Int64,
  file_bytes : Int64,
  release_confirmed : () -> Bool,
  stream_batch? : Int? = None,
) -> NativeNodeRun raise NodeHostFailure {
  if stream_batch is Some(bytes) &&
    (
      bytes <= 0 ||
      bytes >
      @acquisition_host.configured_native_host_limits(setup).transport.max_bytes
    ) {
    raise Physical(InvalidLimits)
  }
  guard (if stream_batch is Some(_) {
      @acquisition_host.configured_retained_native_capacity(setup)
    } else {
      @acquisition_host.configured_native_capacity(setup)
    })
    is Some(capacity) else {
    raise Physical(InvalidLimits)
  }
  if file_bytes < 0L ||
    file_bytes > 9223372036854775807L - capacity.retained_bytes ||
    execution < 0L ||
    execution > 9223372036854775807L - capacity.execution_bytes {
    raise Physical(InvalidLimits)
  }
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      transfer,
      capacity.retained_bytes + file_bytes,
      execution + capacity.execution_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise Physical(issue)
  }
  match @acquisition_host.start_configured_native_host(setup, nonce, verify) {
    Err(issue) => {
      @resources.settle_reservation(ledger, reservation) |> ignore
      raise Host(issue)
    }
    Ok(host) => {
      let limits = @acquisition_host.configured_native_host_limits(setup)
      if stream_batch is Some(bytes) {
        match
          @duckdb_query.stream_duckdb_native_output(
            @acquisition_host.native_host_attempt(host),
            limits.output_rows,
            limits.retention,
            limits.completion.receipts,
            bytes,
            limits.transport.max_rows,
          ) {
          Ok(_) => ()
          Err(issue) => {
            // No transport callback or native resource can have started yet.
            @acquisition_host.close_native_host(host)
            @resources.settle_reservation(ledger, reservation) |> ignore
            raise Host(Attempt(issue))
          }
        }
      }
      {
        streaming_output: stream_batch is Some(_),
        stream_owner: Ref(true),
        host,
        limits: @acquisition_host.configured_native_host_limits(setup),
        physical: Some({
          ledger,
          reservation,
          retention: capacity.retained_bytes + file_bytes,
          file_capacity: file_bytes,
          sealed_file_bytes: None,
          scratch: capacity.execution_bytes,
          release_confirmed,
          settled: false,
          closed: false,
          completed: false,
          holding: None,
          dag: None,
          capture: None,
          source: None,
          observation: None,
        }),
      }
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
  } else {
    @resources.settle_execution_reservation(
      p.ledger,
      p.reservation,
      remaining_execution=if p.closed { 0L } else { p.scratch },
    )
  }
  match result {
    Ok(_) =>
      if confirmed {
        p.settled = true
        refresh_native_physical(run)
      }
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
    p.holding is Some(_) else {
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
  native_host_retain_captured_task(run, dag, 0, observation)
  dag
}

///|
/// Transfer this issuer's exact completed capture into its validated DAG slot.
/// The original reservation/holding and physical cleanup owner remain intact.
#export_name("nativeHostRetainCapturedTask")
pub fn native_host_retain_captured_task(
  run : NativeNodeRun,
  dag : @strategy.CapturedDAG,
  task : Int,
  observation : @duckdb_query.DuckDBNativeObservation,
) -> Unit raise NodeHostFailure {
  guard run.physical is Some(p) &&
    !p.closed &&
    p.completed &&
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
    @strategy.retain_captured_task_allocation(
      dag,
      task,
      holding,
      // Closing a DAG cannot release storage still exposed by the issuer's
      // source/evidence handle. Native close and external cleanup are separate.
      release_confirmed=fn() { p.closed && (p.release_confirmed)() },
    ) {
    Ok(_) => {
      p.dag = Some((dag, task))
      p.holding = None
    }
    Err(issue) => raise Physical(issue)
  }
}

///|
fn close_native_physical(run : NativeNodeRun) -> Unit {
  guard run.physical is Some(p) && !p.closed else { return }
  p.closed = true
  p.source = None
  p.capture = None
  p.observation = None
  if p.dag is Some((dag, task)) {
    @strategy.close_captured_task_output(dag, task)
  }
  refresh_native_physical(run)
}

///|
fn refresh_native_physical(run : NativeNodeRun) -> Unit {
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
#export_name("nativeHostPhysicalRefresh")
pub fn native_host_physical_refresh(run : NativeNodeRun) -> Unit {
  refresh_native_physical(run)
}
