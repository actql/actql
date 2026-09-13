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
  limits : QueryEvidenceLimits,
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
  if records.bytes > limits.max_bytes || records.nodes > limits.max_nodes {
    let issue = MockEvidenceIssue::Encoding(@encode.OutputLimit)
    attempt.state = Failed(Evidence(issue))
    return Err(issue)
  }
  let budget : QueryMaterialBudget = {
    work: 0,
    bytes: limits.max_bytes - records.bytes,
    nodes: limits.max_nodes - records.nodes,
    depth: limits.max_depth,
  }
  try {
    let material = records.retention._requirement.material
    let request_cid = material_hash(budget, writer => {
      @encode.emit_document(writer, material.request)
    })
    if request_cid != material.request_cid {
      attempt.state = Failed(Evidence(ForeignRecords))
      return Err(ForeignRecords)
    }
    let (document, cid) = query_record_document(budget, writer => {
      emit_query_observation(
        records.retention._requirement,
        records._payload,
        records.cids,
        writer,
      )
    })
    let value : MockQueryObservation = {
      records,
      document,
      cid,
      bytes: limits.max_bytes - budget.bytes,
      nodes: limits.max_nodes - budget.nodes,
    }
    attempt.state = Captured(value)
    Ok(value)
  } catch {
    issue => {
      attempt.state = Failed(Evidence(Encoding(issue)))
      Err(Encoding(issue))
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
  @execution.bind_completed_input(
    receiver,
    input_index,
    expected_producer,
    observation.records.retention.computation.output,
  ).map_err(issue => Consumer(issue))
}
