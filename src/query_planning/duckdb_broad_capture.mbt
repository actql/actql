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
  limits : QueryEvidenceLimits,
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
  if records.bytes > limits.max_bytes || records.nodes > limits.max_nodes {
    abort_duckdb_broad_attempt(attempt)
    return Err(Encoding(@encode.OutputLimit))
  }
  let budget : QueryMaterialBudget = {
    work: 0,
    bytes: limits.max_bytes - records.bytes,
    nodes: limits.max_nodes - records.nodes,
    depth: limits.max_depth,
  }
  try {
    let requirement = records.retention.preparation.requirement
    let material = requirement.material
    let request_cid = material_hash(budget, writer => {
      @encode.emit_document(writer, material.request)
    })
    if request_cid != material.request_cid {
      abort_duckdb_broad_attempt(attempt)
      return Err(ForeignRecords)
    }
    let (document, cid) = query_record_document(budget, writer => {
      emit_query_observation(requirement, records.payload, records.cids, writer)
    })
    let observation : DuckDBBroadObservation = {
      records,
      document,
      cid,
      bytes: limits.max_bytes - budget.bytes,
      nodes: limits.max_nodes - budget.nodes,
    }
    attempt.state = Captured(observation)
    Ok(observation)
  } catch {
    issue => {
      abort_duckdb_broad_attempt(attempt)
      Err(Encoding(issue))
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
  @execution.bind_completed_input(
    receiver,
    input_index,
    expected_producer,
    observation.records.retention.output,
  ).map_err(issue => Consumer(issue))
}
