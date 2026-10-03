///|
/// Borrow the settled scan under the existing Host's exact acquisition owner.
/// The returned callback remains the authority check for every bounded read.
pub fn prepare_broad_host_residual_input(
  run : BroadHostRun,
) -> Result[
  (
    @query.QuerySequence,
    @query.QueryReceipt,
    () -> Bool,
    @planning.QueryLogicalGuards,
    @duckdb_query.DuckDBBroadCompletionLimits,
  ),
  BroadHostIssue,
] {
  if run.closed {
    return Err(InvalidState)
  }
  let receipt = match
    @duckdb_query.prepare_duckdb_broad_capture_input(run.issuer, run.attempt) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let requirement = run.configuration.requirement
  Ok(
    (
      @planning.query_material_owner(
        @planning.query_requirement_material(requirement),
      ),
      receipt,
      fn() {
        !run.closed &&
        @duckdb_query.duckdb_broad_capture_input_live(
          run.issuer,
          run.attempt,
          receipt,
        )
      },
      @planning.query_requirement_guards(requirement),
      run.configuration.limits.completion,
    ),
  )
}

///|
pub fn complete_broad_host_bounded_residual(
  run : BroadHostRun,
  receipt : @query.QueryReceipt,
  verify : (
    @query.QuerySequence,
    @query.QueryReceipt,
    @planning.QueryLogicalGuards,
    @duckdb_query.DuckDBBroadCompletionLimits,
  ) -> @execution.CompletedOutput?,
  cleanup : () -> Result[Bool, @connector.FixedComputeIssue],
) -> Result[@duckdb_query.DuckDBBroadObservation, BroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  @duckdb_query.complete_duckdb_broad_bounded_capture(
    run.issuer,
    run.attempt,
    receipt,
    verify,
    cleanup,
    run.configuration.limits.completion,
  ).map_err(issue => Evidence(issue))
}

///|
/// Call only after the residual confirms physical stop. Revocation prevents
/// further consumer access; a failed cleanup remains reachable on the run.
pub fn cleanup_broad_host_residual(
  run : BroadHostRun,
) -> Result[Bool, @connector.FixedComputeIssue] {
  close_broad_host(run)
  @duckdb_query.cleanup_duckdb_broad_residual(run.attempt)
}
