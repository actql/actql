///|
/// Trusted Host wiring only. The standard Node entry constructs the transport
/// verifier internally. Choice freezes before any temporary DB or import work.
pub fn start_captured_duckdb_task(
  run : CapturedDAG,
  task : Int,
  choice : @planning.FixedComputeChoice,
  prepared : @planning.PreparedCompute[@duckdb.FixedCompute],
  generated : @execution.GeneratedSequence,
  limits : @planning.DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
  transfer_bytes : Int64,
  native_execution_bytes : Int64,
  verify : (@planning.DuckDBComputeAttempt) -> Bool,
) -> Result[@planning.DuckDBComputeAttempt, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) {
    return Err(NotReady)
  }
  let request = @planning.fixed_compute_candidate_request(
    @planning.prepared_compute_candidate(prepared),
  )
  if !strategy_candidate_matches(
      run,
      task,
      @planning.prepared_compute_candidate(prepared),
    ) {
    return Err(ForeignCandidate)
  }
  guard run.inputs[task] is Some(read) &&
    physical_equal(read, @planning.fixed_compute_request_input(request)) else {
    return Err(ForeignCandidate)
  }
  guard duckdb_task_retention_capacity(limits) is Some(retention) &&
    duckdb_task_scratch_capacity(limits, transport) is Some(scratch) &&
    transfer_bytes > 0L &&
    native_execution_bytes > 0L &&
    native_execution_bytes <= 9223372036854775807L - scratch else {
    return Err(Physical(InvalidLimits))
  }
  let execution = native_execution_bytes + scratch
  if strategy_task_envelope(run, task) is Some(capacity) &&
    (
      transfer_bytes > capacity.transfer_bytes ||
      retention > capacity.retained_bytes ||
      execution > capacity.execution_bytes
    ) {
    return Err(Physical(InvalidCharge))
  }
  // This boundary creates its own initial reservation for the exact run/task,
  // current selection and configuration; caller-owned tokens cannot be reused.
  let reservation = match
    reserve_attempt(run.ledger, transfer_bytes, retention, execution) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  match
    @planning.start_duckdb_compute_attempt(
      choice, prepared, generated, limits, verify,
    ) {
    Ok(attempt) => {
      run.native_resources[task] = Some({
        attempt,
        reservation,
        retention,
        scratch,
        native_settled: false,
        disposed: false,
        failed_holding: None,
      })
      run.running = Some((task, attempt))
      Ok(attempt)
    }
    Err(issue) => {
      // No native work has started: only synchronous admission failed.
      settle_reservation(run.ledger, reservation) |> ignore
      fail_captured_task(run, task, DuckDB(issue))
      Err(DuckDB(issue))
    }
  }
}

///|
/// Exact owned attempt only: cannot accept unrelated successful outputs, even
/// from the same checked owner and identical input contents. Existing completion
/// verifies transport, capacity, demand and retention before recording success.
pub fn complete_captured_duckdb_task(
  run : CapturedDAG,
  attempt : @planning.DuckDBComputeAttempt,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard run.running is Some((task, expected)) &&
    physical_equal(expected, attempt) else {
    return Err(ForeignCandidate)
  }
  guard run.native_resources[task] is Some(resource) &&
    physical_equal(resource.attempt, attempt) &&
    !resource.disposed &&
    resource.native_settled else {
    return Err(Physical(InvalidCharge))
  }
  let holding = match
    retain_allocation(run.ledger, resource.reservation, resource.retention) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  match @planning.complete_duckdb_compute_attempt(attempt) {
    Ok(output) => {
      run.completed[task] = Some(DuckDB(output))
      record_task_retention(run, task)
      run.resources[task].unwrap().holding = Some(holding)
      settle_reservation(run.ledger, resource.reservation) |> ignore
      run.inputs[task] = None
      run.running = None
      run.generation += 1
      Ok(())
    }
    Err(issue) => {
      // Provisional buffers remain accounted until explicit disposal.
      resource.failed_holding = Some(holding)
      fail_captured_task(run, task, DuckDB(issue))
      Err(DuckDB(issue))
    }
  }
}
