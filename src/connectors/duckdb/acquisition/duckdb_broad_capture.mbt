///|
/// Same-process immutable observation, not durable Run publication.
struct DuckDBBroadObservation {
  records : DuckDBBroadRecords
  captured : @planning.QueryEvidenceCaptured[
    DuckDBQueryIssuer,
    DuckDBBroadAttempt,
    DuckDBBroadRetention,
  ]
}

///|
pub fn capture_duckdb_broad_query(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
  records : DuckDBBroadRecords,
  limits : @planning.QueryEvidenceLimits,
) -> Result[DuckDBBroadObservation, DuckDBEvidenceIssue] {
  match verify_duckdb_broad_records(issuer, attempt, records) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if attempt.state is Captured(_) {
    return Err(AlreadyCaptured)
  }
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  match
    @planning.capture_query_evidence(
      records.issued,
      issuer.registration,
      records.authority.token,
      issuer,
      attempt,
      records.retention,
      limits,
    ) {
    Ok(captured) => {
      let observation : DuckDBBroadObservation = { records, captured, }
      attempt.state = Captured(observation)
      Ok(observation)
    }
    Err(issue) => {
      abort_duckdb_broad_attempt(attempt)
      Err(duckdb_custody_issue(issue))
    }
  }
}

///|
pub fn duckdb_broad_observation_document(
  value : DuckDBBroadObservation,
) -> @encode.EncodedDocument {
  @planning.query_evidence_capture_document(value.captured)
}

///|
pub fn duckdb_broad_observation_cid(value : DuckDBBroadObservation) -> String {
  @planning.query_evidence_capture_cid(value.captured)
}

///|
pub fn duckdb_broad_observation_usage(
  value : DuckDBBroadObservation,
) -> (Int, Int) {
  @planning.query_evidence_capture_usage(value.captured)
}

///|
pub fn bind_captured_duckdb_broad_input(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
  observation : DuckDBBroadObservation,
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
) -> Result[@execution.BoundProducerInput, DuckDBEvidenceIssue] {
  match verify_duckdb_broad_records(issuer, attempt, observation.records) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard attempt.state is Captured(actual) && physical_equal(actual, observation) else {
    return Err(ForeignObservation)
  }
  match
    @planning.verify_query_evidence_captured(
      observation.captured,
      issuer.registration,
      observation.records.authority.token,
      issuer,
      attempt,
      observation.records.retention,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(duckdb_custody_issue(issue))
  }
  @execution.bind_live_completed_input(
    receiver,
    input_index,
    expected_producer,
    observation.records.retention.output,
    fn() {
      verify_duckdb_broad_records(issuer, attempt, observation.records) is Ok(_) &&
      attempt.state is Captured(actual) &&
      physical_equal(actual, observation) &&
      @planning.verify_query_evidence_captured(
        observation.captured,
        issuer.registration,
        observation.records.authority.token,
        issuer,
        attempt,
        observation.records.retention,
      )
      is Ok(_)
    },
  ).map_err(issue => Consumer(issue))
}
