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
fn emit_mock_observation(
  records : MockQueryRecords,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let requirement = records.retention._requirement
  let payload = records._payload
  @encode.begin_object(writer)
  @encode.key(writer, "actual_access")
  emit_query_access(payload.access, writer)
  @encode.key(writer, "coverage")
  @encode.begin_object(writer)
  @encode.key(writer, "complete")
  @encode.bool_value(writer, true)
  @encode.key(writer, "filter_evidence_cid")
  @encode.string_value(writer, records.cids[1])
  @encode.key(writer, "scope_cid")
  @encode.string_value(writer, payload.scan_scope_cid)
  @encode.key(writer, "select_evidence_cid")
  @encode.string_value(writer, records.cids[2])
  @encode.key(writer, "source_validation_evidence_cid")
  @encode.string_value(writer, records.cids[0])
  @encode.end_object(writer)
  @encode.key(writer, "output")
  emit_query_output(payload.output, writer)
  @encode.key(writer, "owner")
  @encode.begin_object(writer)
  @encode.key(writer, "input")
  @encode.string_value(writer, requirement.input)
  @encode.key(writer, "program_source_cid")
  @encode.string_value(
    writer,
    @context.program_identity_definition_cid(requirement.program),
  )
  @encode.key(writer, "stage")
  @encode.string_value(writer, requirement.stage)
  @encode.end_object(writer)
  @encode.key(writer, "parameter_values_cid")
  @encode.string_value(writer, requirement.material.parameter_values_cid)
  @encode.key(writer, "requirement_cid")
  @encode.string_value(writer, requirement.cid)
  @encode.key(writer, "resolved_request_cid")
  @encode.string_value(writer, requirement.material.request_cid)
  @encode.key(writer, "retention")
  @encode.string_value(writer, "process")
  @encode.key(writer, "snapshot")
  emit_query_snapshot(payload.snapshot, writer)
  @encode.key(writer, "source_contract_cid")
  @encode.string_value(writer, requirement.source_contract_cid)
  @encode.key(writer, "source_ref")
  @encode.string_value(writer, requirement.source_ref)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-query-observation/0.1")
  @encode.end_object(writer)
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
      emit_mock_observation(records, writer)
    })
    let value = {
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
