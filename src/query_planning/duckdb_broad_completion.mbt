///|
/// Host-selected allowances for the Local residual and physical evidence work.
/// Requirement-owned acquisition guards remain mandatory and independent.
pub(all) struct DuckDBBroadCompletionLimits {
  execution : @execution.SequenceExecutionLimits
  guards : @query.QueryGuardMeasureLimits
  retention : QueryRetentionLimits
  records : QueryMaterialLimits
  capture : QueryEvidenceLimits
}

///|
/// Complete only the selected broad attempt after exact trusted settlement.
/// Residual evaluation precedes capture; consumers cannot run inside this step.
pub fn complete_duckdb_broad_capture(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
  limits : DuckDBBroadCompletionLimits,
) -> Result[DuckDBBroadObservation, DuckDBEvidenceIssue] {
  if !issuer.live {
    return Err(IssuerClosed)
  }
  guard attempt.authority is Some(authority) &&
    physical_equal(authority.issuer, issuer) else {
    return Err(UnauthorizedAttempt)
  }
  if attempt.state is Captured(_) {
    return Err(AlreadyCaptured)
  }
  if !(issuer.transport_matches)(attempt) {
    abort_duckdb_broad_attempt(attempt)
    return Err(UnverifiedTransport)
  }
  let result = complete_duckdb_broad_capture_impl(issuer, attempt, limits)
  if result is Err(_) {
    abort_duckdb_broad_attempt(attempt)
  }
  result
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
