///|
/// Explicit trusted mock Host setup, outside offers. The Host supplies a fresh
/// process nonce; this module allocates issuer and attempt suffixes itself.
/// This is not a real provider authorization or a portable evidence authority.
struct MockQueryIssuer {
  _contracts : @planning.QueryEvidenceContracts
  requirement : @planning.QueryRequirement
  name : String
  attempts : @planning.IssuerCounter
  mut live : Bool
}

///|
let mock_issuer_serial : @planning.IssuerCounter = @planning.issuer_counter()

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
  contracts : @planning.QueryEvidenceContracts,
  requirement : @planning.QueryRequirement,
  process_nonce : String,
  max_nonce_chars : Int,
) -> Result[MockQueryIssuer, MockEvidenceIssue] {
  if max_nonce_chars < 0 {
    return Err(InvalidLimits)
  }
  if process_nonce.is_empty() || process_nonce.length() > max_nonce_chars {
    return Err(IdentifierLimit)
  }
  guard @planning.reserve_issuer_number(mock_issuer_serial) is Some(serial) else {
    return Err(IdentifierExhausted)
  }
  Ok({
    _contracts: contracts,
    requirement,
    name: process_nonce + "/mock-issuer/" + serial.to_string(),
    attempts: @planning.issuer_counter(),
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
  guard @planning.reserve_issuer_number(issuer.attempts) is Some(number) else {
    return Err(IdentifierExhausted)
  }
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
  Ok({ ..prepared, authority: Some({ issuer, number: number.to_string(), }), })
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
  artifacts : @planning.QueryRecordArtifacts
}

///|
fn mock_artifact_issue(
  issue : @planning.QueryArtifactIssue,
) -> MockEvidenceIssue {
  match issue {
    InvalidLimits => InvalidLimits
    InvalidRetainedLayout => InvalidRetainedLayout
    FieldLimit => FieldLimit
    WorkLimit => WorkLimit
    ForeignMaterial => ForeignRecords
    Encoding(issue) => Encoding(issue)
  }
}

///|
fn build_mock_records(
  authority : MockAttemptAuthority,
  retained : MockQueryRetention,
  limits : @planning.QueryMaterialLimits,
) -> Result[MockQueryRecords, MockEvidenceIssue] {
  // Validate before looking up the schema, preserving prior failure precedence.
  if limits.max_work < 0 ||
    limits.max_fields < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let requirement = retained._requirement
  let query = @query.query_sequence_requirement(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
  )
  let native = retained.computation.strategy.offer.realization == NativeQuery
  let target = if native {
    @sourcequery.query_acquisition_capture(query)
  } else {
    @sourcequery.query_acquisition_input(query)
  }
  guard @pipeline.schema_at(
      @sourcequery.query_acquisition_pipeline(query),
      target,
    )
    is Some(schema) else {
    return Err(InvalidRetainedLayout)
  }
  @planning.build_query_record_artifacts(
    requirement,
    if native {
      retained.output
    } else {
      retained.scan
    },
    retained.output,
    schema,
    authority.issuer.name,
    authority.number,
    limits,
  )
  .map(artifacts => { authority, retention: retained, artifacts, })
  .map_err(mock_artifact_issue)
}

///|
pub fn issue_mock_query_records(
  attempt : MockQueryAttempt,
  limits : @planning.QueryMaterialLimits,
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
  @planning.query_record_artifact_at(records.artifacts, index)
}

///|
pub fn mock_query_record_usage(records : MockQueryRecords) -> (Int, Int) {
  @planning.query_record_artifact_usage(records.artifacts)
}
