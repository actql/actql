///|
/// Materialization owned by an already successful native observation. This
/// cannot be built from caller-supplied rows/CIDs or a replacement verifier.
struct DuckDBNativeOutput {
  issuer : DuckDBNativeIssuer
  attempt : DuckDBNativeAttempt
  observation : DuckDBNativeObservation
  retained : @duckdb.NativeOutputRows
}

///|
/// Separate bounded conversion for a row consumer. Failure preserves the source
/// observation; retry requires fresh conversion allowances, never a source read.
pub fn materialize_duckdb_native_output(
  issuer : DuckDBNativeIssuer,
  attempt : DuckDBNativeAttempt,
  observation : DuckDBNativeObservation,
  max_rows : Int,
  limits : @execution.ValueLimits,
) -> Result[DuckDBNativeOutput, DuckDBEvidenceIssue] {
  match verify_duckdb_native_observation(issuer, attempt, observation) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  @duckdb.retain_native_output_rows(attempt.receiver, max_rows, limits)
  .map(retained => { issuer, attempt, observation, retained, })
  .map_err(issue => NativeOutput(issue))
}

///|
/// Read-only owned material, not an engine CompletedOutput constructor. Checking
/// live provenance remains mandatory before a later producer/completion binding.
pub fn duckdb_native_output_rows(
  output : DuckDBNativeOutput,
) -> Result[@execution.AdmittedOutputRows, DuckDBEvidenceIssue] {
  match
    verify_duckdb_native_observation(
      output.issuer,
      output.attempt,
      output.observation,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !@duckdb.native_output_rows_match(output.retained, output.attempt.receiver) {
    return Err(InvalidRetainedLayout)
  }
  match @duckdb.native_output_rows(output.retained) {
    Some(rows) => Ok(rows)
    None => Err(InvalidRetainedLayout)
  }
}
