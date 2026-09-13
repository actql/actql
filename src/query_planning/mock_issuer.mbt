///|
/// Explicit trusted mock Host setup, outside offers. The Host supplies a fresh
/// process nonce; this module allocates issuer and attempt suffixes itself.
/// This is not a real provider authorization or a portable evidence authority.
struct MockQueryIssuer {
  _contracts : QueryEvidenceContracts
  requirement : QueryRequirement
  name : String
  mut next_attempt : Int
  mut live : Bool
}

///|
priv struct MockIssuerSerial {
  mut next : Int
}

///|
let mock_issuer_serial : MockIssuerSerial = { next: 0, }

///|
priv struct MockAttemptAuthority {
  issuer : MockQueryIssuer
  number : String
}

///|
pub(all) enum MockEvidenceIssue {
  InvalidLimits
  IdentifierLimit
  IssuerClosed
  IdentifierExhausted
  Attempt(MockQueryIssue)
  UnauthorizedAttempt
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
pub fn prepare_mock_query_issuer(
  contracts : QueryEvidenceContracts,
  requirement : QueryRequirement,
  process_nonce : String,
  max_nonce_chars : Int,
) -> Result[MockQueryIssuer, MockEvidenceIssue] {
  if max_nonce_chars < 0 {
    return Err(InvalidLimits)
  }
  if process_nonce.is_empty() || process_nonce.length() > max_nonce_chars {
    return Err(IdentifierLimit)
  }
  if mock_issuer_serial.next == 2147483647 {
    return Err(IdentifierExhausted)
  }
  let serial = mock_issuer_serial.next
  mock_issuer_serial.next += 1
  Ok({
    _contracts: contracts,
    requirement,
    name: process_nonce + "/mock-issuer/" + serial.to_string(),
    next_attempt: 0,
    live: true,
  })
}

///|
/// The attempt identity is allocated before any execution. Offers, supplied
/// rows and record JSON cannot choose it or attach an issuer after execution.
pub fn prepare_issued_mock_query_attempt(
  issuer : MockQueryIssuer,
  strategy : QueryStrategy,
  source : Array[@decode.Cursor],
  max_entries : Int,
) -> Result[MockQueryAttempt, MockEvidenceIssue] {
  if !issuer.live {
    return Err(IssuerClosed)
  }
  if issuer.next_attempt == 2147483647 {
    return Err(IdentifierExhausted)
  }
  let number = issuer.next_attempt.to_string()
  issuer.next_attempt += 1
  let prepared = match
    prepare_requirement_mock_query_attempt(
      issuer.requirement,
      strategy,
      source,
      max_entries,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Attempt(issue))
  }
  Ok({ ..prepared, authority: Some({ issuer, number, }), })
}

///|
pub fn close_mock_query_issuer(issuer : MockQueryIssuer) -> Unit {
  issuer.live = false
}

///|
/// Host diagnostic identities allocated before execution, not authority tokens
/// or future content CIDs. No reader can attach them to a different task.
pub fn mock_query_attempt_identity(
  attempt : MockQueryAttempt,
) -> (String, String)? {
  attempt.authority.map(authority => (authority.issuer.name, authority.number))
}

///|
/// Three records issued atomically, still before observation capture. Private
/// arrays/documents are immutable to callers; verification also requires the
/// exact live task and its issued-set handle, never CID lookup alone.
struct MockQueryRecords {
  authority : MockAttemptAuthority
  retention : MockQueryRetention
  _payload : QueryRecordPayload
  documents : Array[@encode.EncodedDocument]
  cids : Array[String]
  bytes : Int
  nodes : Int
}

///|
fn mock_record_payload(
  retained : MockQueryRetention,
  limits : QueryMaterialLimits,
  budget : QueryMaterialBudget,
) -> Result[QueryRecordPayload, MockEvidenceIssue] {
  let requirement = retained._requirement
  let computation = retained.computation
  let query = @query.query_sequence_requirement(requirement.material.owner)
  let native = computation.strategy.offer.realization == NativeQuery
  let target = if native {
    @acquisition.query_acquisition_capture(query)
  } else {
    @acquisition.query_acquisition_input(query)
  }
  guard @pipeline.schema_at(
      @acquisition.query_acquisition_pipeline(query),
      target,
    )
    is Some(schema) else {
    return Err(InvalidRetainedLayout)
  }
  query_record_payload(
    requirement,
    if native {
      retained.output
    } else {
      retained.scan
    },
    retained.output,
    schema,
    limits,
    budget,
  ).map_err(issue => {
    match issue {
      InvalidRetainedLayout => InvalidRetainedLayout
      FieldLimit => FieldLimit
      WorkLimit => WorkLimit
      Encoding(issue) => Encoding(issue)
    }
  })
}

///|
fn build_mock_records(
  authority : MockAttemptAuthority,
  retained : MockQueryRetention,
  limits : QueryMaterialLimits,
) -> Result[MockQueryRecords, MockEvidenceIssue] {
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
  let payload = match mock_record_payload(retained, limits, budget) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let documents : Array[@encode.EncodedDocument] = []
  let cids : Array[String] = []
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
      _payload: payload,
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
pub fn issue_mock_query_records(
  attempt : MockQueryAttempt,
  limits : QueryMaterialLimits,
) -> Result[MockQueryRecords, MockEvidenceIssue] {
  guard attempt.authority is Some(authority) else {
    return Err(UnauthorizedAttempt)
  }
  if !authority.issuer.live {
    return Err(IssuerClosed)
  }
  guard attempt.state is Retained(retained) else { return Err(NotRetained) }
  if !physical_equal(authority.issuer.requirement, retained._requirement) {
    return Err(UnauthorizedAttempt)
  }
  match build_mock_records(authority, retained, limits) {
    Ok(records) => {
      attempt.state = EvidenceIssued(records)
      Ok(records)
    }
    Err(issue) => {
      attempt.state = Failed(Evidence(issue))
      Err(issue)
    }
  }
}

///|
pub fn verify_mock_query_records(
  issuer : MockQueryIssuer,
  attempt : MockQueryAttempt,
  records : MockQueryRecords,
) -> Result[Unit, MockEvidenceIssue] {
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
  guard actual is Some(actual) && physical_equal(actual, records) else {
    return Err(ForeignRecords)
  }
  if !physical_equal(issuer.requirement, records.retention._requirement) ||
    !@execution.row_wire_matches_captured(
      records.retention.scan,
      @query.query_receipt_rows(records.retention.computation._scan),
    ) ||
    !@execution.row_wire_matches_output(
      records.retention.output,
      records.retention.computation.output,
    ) {
    return Err(ForeignRecords)
  }
  Ok(())
}

///|
/// Index 0/1/2 is source_validation/filter/select. Wire data is diagnostic,
/// never an alternative to the opaque issued set and expected live attempt.
pub fn mock_query_record_at(
  records : MockQueryRecords,
  index : Int,
) -> (@encode.EncodedDocument, String)? {
  guard records.documents.get(index) is Some(document) &&
    records.cids.get(index) is Some(cid) else {
    return None
  }
  Some((document, cid))
}

///|
pub fn mock_query_record_usage(records : MockQueryRecords) -> (Int, Int) {
  (records.bytes, records.nodes)
}
