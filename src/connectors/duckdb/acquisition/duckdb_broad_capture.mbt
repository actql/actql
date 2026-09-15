///|
/// Same-process immutable observation, not durable Run publication.
struct DuckDBBroadObservation {
  records : DuckDBBroadRecords
  document : @encode.EncodedDocument
  cid : String
  bytes : Int
  nodes : Int
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
  match @planning.build_query_observation_artifact(records.artifacts, limits) {
    Ok((document, cid, bytes, nodes)) => {
      let observation : DuckDBBroadObservation = {
        records,
        document,
        cid,
        bytes,
        nodes,
      }
      attempt.state = Captured(observation)
      Ok(observation)
    }
    Err(issue) => {
      abort_duckdb_broad_attempt(attempt)
      Err(duckdb_artifact_issue(issue))
    }
  }
}

///|
pub fn duckdb_broad_observation_document(
  value : DuckDBBroadObservation,
) -> @encode.EncodedDocument {
  value.document
}

///|
pub fn duckdb_broad_observation_cid(value : DuckDBBroadObservation) -> String {
  value.cid
}

///|
pub fn duckdb_broad_observation_usage(
  value : DuckDBBroadObservation,
) -> (Int, Int) {
  (value.bytes, value.nodes)
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
  @execution.bind_live_completed_input(
    receiver,
    input_index,
    expected_producer,
    observation.records.retention.output,
    fn() {
      verify_duckdb_broad_records(issuer, attempt, observation.records) is Ok(_) &&
      attempt.state is Captured(actual) &&
      physical_equal(actual, observation)
    },
  ).map_err(issue => Consumer(issue))
}
