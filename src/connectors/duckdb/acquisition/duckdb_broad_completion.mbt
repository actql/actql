///|
/// Host-selected allowances for the Local residual and physical evidence work.
/// Requirement-owned acquisition guards remain mandatory and independent.
pub(all) struct DuckDBBroadCompletionLimits {
  execution : @execution.SequenceExecutionLimits
  guards : @query.QueryGuardMeasureLimits
  retention : @planning.QueryRetentionLimits
  records : @planning.QueryMaterialLimits
  capture : @planning.QueryEvidenceLimits
}

///|
/// Hand the settled scan to the existing bounded residual executor. This is
/// input admission only: it issues neither capture nor completion evidence.
/// The attempt remains the owner of the scan while its residual is executing.
pub fn prepare_duckdb_broad_capture_input(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
) -> Result[@query.QueryReceipt, DuckDBEvidenceIssue] {
  match validate_duckdb_broad_capture_transport(issuer, attempt) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match settle_duckdb_broad_transport(attempt) {
    Ok(_) => ()
    Err(issue) => return Err(BroadAttempt(issue))
  }
  guard attempt.state is Ready(input) else {
    return Err(BroadAttempt(InvalidState))
  }
  @query.bind_query_receipt(
    @planning.query_material_owner(
      @planning.query_requirement_material(attempt.preparation.requirement),
    ),
    input,
  ).map_err(issue => BroadAttempt(Residual(Execution(issue))))
}

///|
/// The bounded input reader must retain this check while borrowing the scan.
/// Possession of a receipt does not extend issuer or transport authority.
pub fn duckdb_broad_capture_input_live(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
  receipt : @query.QueryReceipt,
) -> Bool {
  guard @planning.query_evidence_registration_live(issuer.registration) &&
    attempt.authority is Some(authority) &&
    physical_equal(authority.issuer, issuer) &&
    attempt.state is Ready(input) &&
    physical_equal(input, @query.query_receipt_rows(receipt)) else {
    return false
  }
  @planning.query_evidence_transport_matches(issuer.registration, attempt)
}

///|
/// Complete only the selected broad attempt after exact trusted settlement.
/// Residual evaluation precedes capture; consumers cannot run inside this step.
pub fn complete_duckdb_broad_capture(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
  limits : DuckDBBroadCompletionLimits,
) -> Result[DuckDBBroadObservation, DuckDBEvidenceIssue] {
  match validate_duckdb_broad_capture_transport(issuer, attempt) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = complete_duckdb_broad_capture_impl(issuer, attempt, limits)
  if result is Err(_) {
    abort_duckdb_broad_attempt(attempt)
  }
  result
}

///|
/// Trusted Host composition, not an adapter-supplied Boolean or serialized
/// evidence. The verifier must return the bounded owner's guarded output for
/// the exact receipt and completion limits. Retain that owner's cleanup across
/// retention/capture failures; neither completion nor retry executes Compute.
pub fn complete_duckdb_broad_bounded_capture(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
  receipt : @query.QueryReceipt,
  verify : (
    @query.QuerySequence,
    @query.QueryReceipt,
    @planning.QueryLogicalGuards,
    DuckDBBroadCompletionLimits,
  ) -> @execution.CompletedOutput?,
  cleanup : () -> Result[Bool, @connector.FixedComputeIssue],
  limits : DuckDBBroadCompletionLimits,
) -> Result[DuckDBBroadObservation, DuckDBEvidenceIssue] {
  match validate_duckdb_broad_capture_transport(issuer, attempt) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard attempt.state is Ready(input) &&
    attempt.residual_cleanup is None &&
    physical_equal(input, @query.query_receipt_rows(receipt)) else {
    return Err(BroadAttempt(InvalidState))
  }
  let requirement = attempt.preparation.requirement
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  guard @query.query_receipt_matches(receipt, query) &&
    verify(
      query,
      receipt,
      @planning.query_requirement_guards(requirement),
      limits,
    )
    is Some(output) &&
    @execution.completed_output_matches_captured_inputs(output, [input]) &&
    @execution.completed_output_matches_port(
      output,
      @query.query_sequence_owner(query),
      @sourcequery.query_acquisition_capture(
        @query.query_sequence_requirement(query),
      ),
    ) else {
    return Err(BroadAttempt(InvalidState))
  }
  attempt.residual_cleanup = Some(cleanup)
  attempt.state = Completed({ _scan: input, output, })
  let result = finish_duckdb_broad_capture(issuer, attempt, limits)
  if result is Err(_) {
    abort_duckdb_broad_attempt(attempt)
  }
  result
}

///|
fn validate_duckdb_broad_capture_transport(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
) -> Result[Unit, DuckDBEvidenceIssue] {
  if !@planning.query_evidence_registration_live(issuer.registration) {
    return Err(IssuerClosed)
  }
  guard attempt.authority is Some(authority) &&
    physical_equal(authority.issuer, issuer) else {
    return Err(UnauthorizedAttempt)
  }
  if attempt.state is Captured(_) {
    return Err(AlreadyCaptured)
  }
  if !@planning.query_evidence_transport_matches(issuer.registration, attempt) {
    abort_duckdb_broad_attempt(attempt)
    return Err(UnverifiedTransport)
  }
  Ok(())
}

///|
fn complete_duckdb_broad_capture_impl(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
  limits : DuckDBBroadCompletionLimits,
) -> Result[DuckDBBroadObservation, DuckDBEvidenceIssue] {
  match settle_duckdb_broad_transport(attempt) {
    Ok(_) => ()
    Err(issue) => return Err(BroadAttempt(issue))
  }
  match execute_duckdb_broad_attempt(attempt, limits.execution, limits.guards) {
    Ok(_) => ()
    Err(issue) => return Err(BroadAttempt(issue))
  }
  finish_duckdb_broad_capture(issuer, attempt, limits)
}

///|
fn finish_duckdb_broad_capture(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
  limits : DuckDBBroadCompletionLimits,
) -> Result[DuckDBBroadObservation, DuckDBEvidenceIssue] {
  match retain_duckdb_broad_attempt(attempt, limits.retention) {
    Ok(_) => ()
    Err(issue) => return Err(BroadAttempt(issue))
  }
  let records = match issue_duckdb_broad_records(attempt, limits.records) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  capture_duckdb_broad_query(issuer, attempt, records, limits.capture)
}
