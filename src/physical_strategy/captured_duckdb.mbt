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
  match
    @planning.start_duckdb_compute_attempt(
      choice, prepared, generated, limits, verify,
    ) {
    Ok(attempt) => {
      run.running = Some((task, attempt))
      Ok(attempt)
    }
    Err(issue) => {
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
  match @planning.complete_duckdb_compute_attempt(attempt) {
    Ok(output) => {
      run.completed[task] = Some(DuckDB(output))
      run.inputs[task] = None
      run.running = None
      run.generation += 1
      Ok(())
    }
    Err(issue) => {
      fail_captured_task(run, task, DuckDB(issue))
      Err(DuckDB(issue))
    }
  }
}
