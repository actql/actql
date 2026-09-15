///|
/// Process-retained completed observation. This is not durable capture, Run
/// publication or an external provider attestation. Its output remains opaque.
struct MockQueryObservation {
  records : MockQueryRecords
  document : @encode.EncodedDocument
  cid : String
  bytes : Int
  nodes : Int
}

///|
/// Verify the live issued set, then construct the exact shared observation.
/// Artifact budgets include prior scope/record work and this serialization/hash;
/// they are not reset between evidence issuance and capture. Row retention and
/// execution retain their separate, already enforced limits.
pub fn capture_mock_query(
  issuer : MockQueryIssuer,
  attempt : MockQueryAttempt,
  records : MockQueryRecords,
  limits : @planning.QueryEvidenceLimits,
) -> Result[MockQueryObservation, MockEvidenceIssue] {
  match verify_mock_query_records(issuer, attempt, records) {
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
      let value : MockQueryObservation = {
        records,
        document,
        cid,
        bytes,
        nodes,
      }
      attempt.state = Captured(value)
      Ok(value)
    }
    Err(issue) => {
      let issue = mock_artifact_issue(issue)
      attempt.state = Failed(Evidence(issue))
      Err(issue)
    }
  }
}

///|
pub fn mock_query_observation_document(
  value : MockQueryObservation,
) -> @encode.EncodedDocument {
  value.document
}

///|
pub fn mock_query_observation_cid(value : MockQueryObservation) -> String {
  value.cid
}

///|
pub fn mock_query_observation_usage(value : MockQueryObservation) -> (Int, Int) {
  (value.bytes, value.nodes)
}

///|
/// The receiving driver's ordinary producer admission, projection and accounting
/// remain authoritative. No raw output getter or source-selector input is used.
pub fn bind_captured_query_input(
  issuer : MockQueryIssuer,
  attempt : MockQueryAttempt,
  observation : MockQueryObservation,
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
) -> Result[@execution.BoundProducerInput, MockEvidenceIssue] {
  match verify_mock_query_records(issuer, attempt, observation.records) {
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
    observation.records.retention.computation.output,
    fn() {
      verify_mock_query_records(issuer, attempt, observation.records) is Ok(_) &&
      attempt.state is Captured(actual) &&
      physical_equal(actual, observation)
    },
  ).map_err(issue => Consumer(issue))
}
