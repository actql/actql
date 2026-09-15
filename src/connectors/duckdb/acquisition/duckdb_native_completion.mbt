///|
/// Host-selected physical/material allowances. Common acquisition guards remain
/// owned by the requirement; these allowances cannot replace or waive them.
pub(all) struct DuckDBNativeCompletionLimits {
  demand : @execution.FixedInputGuardMeasureLimits
  receipts : @execution.RowWireLimits
  max_received_rows : Int
  max_received_bytes : Int
  max_retained_wire_bytes : Int
  records : @planning.QueryMaterialLimits
  capture : @planning.QueryEvidenceLimits
}

///|
/// Trusted Host calls this only after the real transport and cleanup settle.
/// The issuer still verifies its exact live transport relationship; this call
/// is not an alternative verifier, serialized authority or engine completion.
/// No Local predicate replay or new source access occurs here.
pub fn complete_duckdb_native_capture(
  issuer : DuckDBNativeIssuer,
  attempt : DuckDBNativeAttempt,
  limits : DuckDBNativeCompletionLimits,
) -> Result[DuckDBNativeObservation, DuckDBEvidenceIssue] {
  // Reject foreign authority before changing either attempt's lifecycle. A
  // successful observation is not revoked by a duplicate completion request.
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
    abort_duckdb_native_attempt(attempt)
    return Err(UnverifiedTransport)
  }
  let result = complete_duckdb_native_capture_impl(issuer, attempt, limits)
  if result is Err(_) {
    abort_duckdb_native_attempt(attempt)
  }
  result
}

///|
fn complete_duckdb_native_capture_impl(
  issuer : DuckDBNativeIssuer,
  attempt : DuckDBNativeAttempt,
  limits : DuckDBNativeCompletionLimits,
) -> Result[DuckDBNativeObservation, DuckDBEvidenceIssue] {
  match settle_duckdb_native_transport(attempt) {
    Ok(_) => ()
    Err(issue) => return Err(NativeAttempt(issue))
  }
  match
    measure_duckdb_native_attempt(
      attempt,
      limits.demand,
      limits.receipts,
      limits.max_received_rows,
      limits.max_received_bytes,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(NativeAttempt(issue))
  }
  let records = match
    issue_duckdb_native_records(
      attempt,
      limits.max_retained_wire_bytes,
      limits.records,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  capture_duckdb_native_query(issuer, attempt, records, limits.capture)
}
