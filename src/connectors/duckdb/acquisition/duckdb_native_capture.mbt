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
  limits : @planning.QueryEvidenceLimits,
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
  guard @planning.query_artifact_budget(
      0,
      limits.max_bytes - records.bytes,
      limits.max_nodes - records.nodes,
      limits.max_depth,
    )
    is Some(budget) else {
    return Err(InvalidLimits)
  }
  try {
    let requirement = issuer.requirement
    if !@planning.query_artifact_request_matches(budget, requirement) {
      abort_duckdb_native_attempt(attempt)
      return Err(ForeignRecords)
    }
    let (document, cid) = @planning.query_record_document(budget, writer => {
      emit_native_observation(records, writer)
    })
    let observation : DuckDBNativeObservation = {
      records,
      document,
      cid,
      bytes: limits.max_bytes - @planning.query_artifact_remaining(budget).1,
      nodes: limits.max_nodes - @planning.query_artifact_remaining(budget).2,
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

///|
/// Logical value-measurement usage for the exact two receipts captured by this
/// observation. Predicate demand is reported separately.
pub fn duckdb_native_observation_measurement_usage(
  value : DuckDBNativeObservation,
) -> (Int, Int, Int) {
  @duckdb.native_receiving_measurement_usage(
    value.records.measurement.attempt.receiver,
  )
}

///|
/// Exact comparison demand established for this observation's validation scan.
pub fn duckdb_native_observation_demand_usage(
  value : DuckDBNativeObservation,
) -> @duckdb.NativeDemandUsage {
  duckdb_native_measured_demand(value.records.measurement)
}

///|
/// Canonical receipt material owned by this exact captured observation.
/// Exposing the document does not transfer issuer authority or make it a
/// durable replay proof.
pub fn duckdb_native_observation_receipt_at(
  value : DuckDBNativeObservation,
  index : Int,
) -> (@encode.EncodedDocument, String)? {
  duckdb_native_receipt_at(value.records, index)
}

///|
/// Canonical process-evidence material owned by this exact observation.
/// The live issuer/attempt checks remain separate from the serialized bytes.
pub fn duckdb_native_observation_record_at(
  value : DuckDBNativeObservation,
  index : Int,
) -> (@encode.EncodedDocument, String)? {
  duckdb_native_record_at(value.records, index)
}
