///|
/// Trusted Host registration, not a Connector wire authority. The callback
/// verifies exact grant/port/read-view/settled transport ownership outside this
/// package. It must never accept a CID, path, SQL-success bool or JSON as proof.
struct DuckDBQueryIssuer {
  _contracts : QueryEvidenceContracts
  requirement : QueryRequirement
  name : String
  mut transport_matches : (DuckDBBroadAttempt) -> Bool
  mut next_attempt : Int
  mut live : Bool
}

///|
priv struct DuckDBIssuerSerial {
  mut next : Int
}

///|
let duckdb_issuer_serial : DuckDBIssuerSerial = { next: 0, }

///|
priv struct DuckDBBroadAuthority {
  issuer : DuckDBQueryIssuer
  number : String
}

///|
pub(all) enum DuckDBEvidenceIssue {
  InvalidLimits
  IdentifierLimit
  IdentifierExhausted
  IssuerClosed
  NotSelected
  UnauthorizedAttempt
  UnverifiedTransport
  NotRetained
  InvalidRetainedLayout
  FieldLimit
  WorkLimit
  Encoding(@encode.EncodeFailure)
  ForeignRecords
  AlreadyCaptured
  ForeignObservation
  Consumer(@execution.ProducerBindingIssue)
}

///|
pub fn prepare_duckdb_query_issuer(
  contracts : QueryEvidenceContracts,
  requirement : QueryRequirement,
  process_nonce : String,
  max_nonce_chars : Int,
  transport_matches : (DuckDBBroadAttempt) -> Bool,
) -> Result[DuckDBQueryIssuer, DuckDBEvidenceIssue] {
  if max_nonce_chars < 0 {
    return Err(InvalidLimits)
  }
  if process_nonce.is_empty() || process_nonce.length() > max_nonce_chars {
    return Err(IdentifierLimit)
  }
  if duckdb_issuer_serial.next == 2147483647 {
    return Err(IdentifierExhausted)
  }
  let serial = duckdb_issuer_serial.next
  duckdb_issuer_serial.next += 1
  Ok({
    _contracts: contracts,
    requirement,
    name: process_nonce + "/duckdb-issuer/" + serial.to_string(),
    transport_matches,
    next_attempt: 0,
    live: true,
  })
}

///|
/// Bind selection and issuer before metadata/row access. No operation attaches
/// authority to an already executed unissued attempt.
pub fn prepare_issued_duckdb_broad_attempt(
  issuer : DuckDBQueryIssuer,
  choice : AcquisitionChoice,
  prepared : PreparedAcquisition[DuckDBQueryPreparation],
) -> Result[DuckDBBroadAttempt, DuckDBEvidenceIssue] {
  if !issuer.live {
    return Err(IssuerClosed)
  }
  guard acquisition_choice_payload(choice, prepared) is Some(preparation) else {
    return Err(NotSelected)
  }
  if !physical_equal(issuer.requirement, preparation.requirement) {
    return Err(UnauthorizedAttempt)
  }
  if issuer.next_attempt == 2147483647 {
    return Err(IdentifierExhausted)
  }
  let number = issuer.next_attempt.to_string()
  issuer.next_attempt += 1
  let attempt = prepare_duckdb_broad_attempt(preparation)
  Ok({ ..attempt, authority: Some({ issuer, number, }), })
}

///|
pub fn close_duckdb_query_issuer(issuer : DuckDBQueryIssuer) -> Unit {
  issuer.live = false
  issuer.transport_matches = _ => false
}

///|
pub fn duckdb_broad_attempt_identity(
  attempt : DuckDBBroadAttempt,
) -> (String, String)? {
  attempt.authority.map(value => (value.issuer.name, value.number))
}

///|
struct DuckDBBroadRecords {
  authority : DuckDBBroadAuthority
  retention : DuckDBBroadRetention
  payload : QueryRecordPayload
  documents : Array[@encode.EncodedDocument]
  cids : Array[String]
  bytes : Int
  nodes : Int
}

///|
fn build_duckdb_broad_records(
  authority : DuckDBBroadAuthority,
  retained : DuckDBBroadRetention,
  limits : QueryMaterialLimits,
) -> Result[DuckDBBroadRecords, DuckDBEvidenceIssue] {
  if limits.max_work < 0 ||
    limits.max_fields < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let budget : QueryMaterialBudget = {
    work: limits.max_work,
    bytes: limits.max_bytes,
    nodes: limits.max_nodes,
    depth: limits.max_depth,
  }
  let requirement = retained.preparation.requirement
  let query = @query.query_sequence_requirement(requirement.material.owner)
  guard @pipeline.schema_at(
      @acquisition.query_acquisition_pipeline(query),
      @acquisition.query_acquisition_input(query),
    )
    is Some(schema) else {
    return Err(InvalidRetainedLayout)
  }
  let payload = match
    query_record_payload(
      requirement,
      retained.measured.scan,
      retained.measured.output,
      schema,
      limits,
      budget,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue {
          InvalidRetainedLayout => InvalidRetainedLayout
          FieldLimit => FieldLimit
          WorkLimit => WorkLimit
          Encoding(issue) => Encoding(issue)
        },
      )
  }
  let documents = []
  let cids = []
  try {
    for role in [SourceValidation, Filter, Select] {
      let (document, cid) = query_record_document(budget, writer => {
        emit_query_record(
          payload,
          authority.issuer.name,
          authority.number,
          role,
          writer,
        )
      })
      documents.push(document)
      cids.push(cid)
    }
    Ok({
      authority,
      retention: retained,
      payload,
      documents,
      cids,
      bytes: limits.max_bytes - budget.bytes,
      nodes: limits.max_nodes - budget.nodes,
    })
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
pub fn issue_duckdb_broad_records(
  attempt : DuckDBBroadAttempt,
  limits : QueryMaterialLimits,
) -> Result[DuckDBBroadRecords, DuckDBEvidenceIssue] {
  guard attempt.authority is Some(authority) else {
    return Err(UnauthorizedAttempt)
  }
  if !authority.issuer.live {
    return Err(IssuerClosed)
  }
  guard attempt.state is Retained(retained) else { return Err(NotRetained) }
  if !physical_equal(
      authority.issuer.requirement,
      retained.preparation.requirement,
    ) ||
    !duckdb_broad_retention_matches(retained, attempt) {
    abort_duckdb_broad_attempt(attempt)
    return Err(UnauthorizedAttempt)
  }
  if !(authority.issuer.transport_matches)(attempt) {
    abort_duckdb_broad_attempt(attempt)
    return Err(UnverifiedTransport)
  }
  match build_duckdb_broad_records(authority, retained, limits) {
    Ok(records) => {
      attempt.state = EvidenceIssued(records)
      Ok(records)
    }
    Err(issue) => {
      abort_duckdb_broad_attempt(attempt)
      Err(issue)
    }
  }
}

///|
pub fn verify_duckdb_broad_records(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
  records : DuckDBBroadRecords,
) -> Result[Unit, DuckDBEvidenceIssue] {
  if !issuer.live {
    return Err(IssuerClosed)
  }
  guard attempt.authority is Some(expected) &&
    physical_equal(expected.issuer, issuer) &&
    physical_equal(records.authority, expected) else {
    return Err(UnauthorizedAttempt)
  }
  let actual = match attempt.state {
    EvidenceIssued(value) => Some(value)
    Captured(value) => Some(value.records)
    _ => None
  }
  guard actual is Some(actual) &&
    physical_equal(actual, records) &&
    physical_equal(
      issuer.requirement,
      records.retention.preparation.requirement,
    ) &&
    duckdb_broad_retention_matches(records.retention, attempt) else {
    return Err(ForeignRecords)
  }
  if !(issuer.transport_matches)(attempt) {
    return Err(UnverifiedTransport)
  }
  Ok(())
}

///|
pub fn duckdb_broad_record_at(
  records : DuckDBBroadRecords,
  index : Int,
) -> (@encode.EncodedDocument, String)? {
  guard records.documents.get(index) is Some(document) &&
    records.cids.get(index) is Some(cid) else {
    return None
  }
  Some((document, cid))
}
