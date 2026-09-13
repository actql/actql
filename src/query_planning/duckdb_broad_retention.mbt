///|
/// Owned immutable scan/output measurement, not execution records or capture.
struct DuckDBBroadRetention {
  preparation : DuckDBQueryPreparation
  completion : DuckDBBroadCompletion
  output : @execution.CompletedOutput
  measured : MeasuredQueryRows
}

///|
pub fn retain_duckdb_broad_attempt(
  attempt : DuckDBBroadAttempt,
  limits : QueryRetentionLimits,
) -> Result[DuckDBBroadRetention, DuckDBBroadAttemptIssue] {
  guard attempt.state is Completed(completion) else {
    return fail_duckdb_broad_attempt(attempt, InvalidState)
  }
  let output = duckdb_broad_attempt_output(attempt).unwrap()
  match measure_query_retention(completion._scan, output, true, limits) {
    Err(issue) => fail_duckdb_broad_attempt(attempt, Retention(issue))
    Ok(measured) => {
      let retained = {
        preparation: attempt.preparation,
        completion,
        output,
        measured,
      }
      attempt.state = Retained(retained)
      Ok(retained)
    }
  }
}

///|
pub fn duckdb_broad_retention_matches(
  retained : DuckDBBroadRetention,
  attempt : DuckDBBroadAttempt,
) -> Bool {
  let current = match attempt.state {
    Retained(value) => value
    EvidenceIssued(value) => value.retention
    Captured(value) => value.records.retention
    _ => return false
  }
  physical_equal(current, retained) &&
  physical_equal(retained.preparation, attempt.preparation) &&
  @execution.row_wire_matches_captured(
    retained.measured.scan,
    retained.completion._scan,
  ) &&
  @execution.row_wire_matches_output(retained.measured.output, retained.output)
}

///|
pub fn duckdb_broad_retention_usage(
  retained : DuckDBBroadRetention,
) -> (Int, Int, Int) {
  (
    retained.measured.received_bytes,
    retained.measured.retained_bytes,
    retained.measured.measured_nodes,
  )
}

///|
pub fn duckdb_broad_retention_cids(
  retained : DuckDBBroadRetention,
) -> (String, String) {
  (
    @execution.row_wire_cid(retained.measured.scan),
    @execution.row_wire_cid(retained.measured.output),
  )
}
