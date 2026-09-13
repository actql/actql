///|
/// Process-local retained native observation. No durable replay authority and
/// no raw engine CompletedOutput constructor is exposed by this handle.
struct DuckDBNativeObservation {
  records : DuckDBNativeRecords
  document : @encode.EncodedDocument
  cid : String
  bytes : Int
  nodes : Int
}

///|
pub fn capture_duckdb_native_query(
  issuer : DuckDBNativeIssuer,
  attempt : DuckDBNativeAttempt,
  records : DuckDBNativeRecords,
  limits : QueryEvidenceLimits,
) -> Result[DuckDBNativeObservation, DuckDBEvidenceIssue] {
  match verify_duckdb_native_records(issuer, attempt, records) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if attempt.state is Captured(_) {
    return Err(AlreadyCaptured)
  }
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if records.bytes > limits.max_bytes || records.nodes > limits.max_nodes {
    abort_duckdb_native_attempt(attempt)
    return Err(Encoding(@encode.OutputLimit))
  }
  let budget : QueryMaterialBudget = {
    work: 0,
    bytes: limits.max_bytes - records.bytes,
    nodes: limits.max_nodes - records.nodes,
    depth: limits.max_depth,
  }
  try {
    let requirement = issuer.requirement
    let request_cid = material_hash(budget, writer => {
      @encode.emit_document(writer, requirement.material.request)
    })
    if request_cid != requirement.material.request_cid {
      abort_duckdb_native_attempt(attempt)
      return Err(ForeignRecords)
    }
    let (document, cid) = query_record_document(budget, writer => {
      emit_native_observation(records, writer)
    })
    let observation : DuckDBNativeObservation = {
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
      abort_duckdb_native_attempt(attempt)
      Err(Encoding(issue))
    }
  }
}

///|
pub fn verify_duckdb_native_observation(
  issuer : DuckDBNativeIssuer,
  attempt : DuckDBNativeAttempt,
  observation : DuckDBNativeObservation,
) -> Result[Unit, DuckDBEvidenceIssue] {
  match verify_duckdb_native_records(issuer, attempt, observation.records) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard attempt.state is Captured(actual) && physical_equal(actual, observation) else {
    return Err(ForeignObservation)
  }
  Ok(())
}

///|
pub fn duckdb_native_observation_document(
  value : DuckDBNativeObservation,
) -> @encode.EncodedDocument {
  value.document
}

///|
pub fn duckdb_native_observation_cid(value : DuckDBNativeObservation) -> String {
  value.cid
}

///|
pub fn duckdb_native_observation_usage(
  value : DuckDBNativeObservation,
) -> (Int, Int) {
  (value.bytes, value.nodes)
}
