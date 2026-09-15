///|
/// Trusted Host registration, not a Connector wire authority. The callback
/// verifies exact grant/port/read-view/settled transport ownership outside this
/// package. It must never accept a CID, path, SQL-success bool or JSON as proof.
struct DuckDBQueryIssuer {
  _contracts : @planning.QueryEvidenceContracts
  requirement : @planning.QueryRequirement
  name : String
  mut transport_matches : (DuckDBBroadAttempt) -> Bool
  attempts : @planning.IssuerCounter
  mut live : Bool
}

///|
let duckdb_issuer_serial : @planning.IssuerCounter = @planning.issuer_counter()

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
  NativeAttempt(DuckDBNativeAttemptIssue)
  BroadAttempt(DuckDBBroadAttemptIssue)
  NativeOutput(@duckdb.NativeOutputRetentionIssue)
}

///|
pub fn prepare_duckdb_query_issuer(
  contracts : @planning.QueryEvidenceContracts,
  requirement : @planning.QueryRequirement,
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
  guard @planning.reserve_issuer_number(duckdb_issuer_serial) is Some(serial) else {
    return Err(IdentifierExhausted)
  }
  Ok({
    _contracts: contracts,
    requirement,
    name: process_nonce + "/duckdb-issuer/" + serial.to_string(),
    transport_matches,
    attempts: @planning.issuer_counter(),
    live: true,
  })
}

///|
/// Bind selection and issuer before metadata/row access. No operation attaches
/// authority to an already executed unissued attempt.
pub fn prepare_issued_duckdb_broad_attempt(
  issuer : DuckDBQueryIssuer,
  choice : @planning.AcquisitionChoice,
  prepared : @planning.PreparedAcquisition[DuckDBQueryPreparation],
) -> Result[DuckDBBroadAttempt, DuckDBEvidenceIssue] {
  if !issuer.live {
    return Err(IssuerClosed)
  }
  guard @planning.acquisition_choice_payload(choice, prepared)
    is Some(preparation) else {
    return Err(NotSelected)
  }
  if !physical_equal(issuer.requirement, preparation.requirement) {
    return Err(UnauthorizedAttempt)
  }
  guard @planning.reserve_issuer_number(issuer.attempts) is Some(number) else {
    return Err(IdentifierExhausted)
  }
  let attempt = prepare_duckdb_broad_attempt(preparation)
  Ok({ ..attempt, authority: Some({ issuer, number: number.to_string(), }), })
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
  artifacts : @planning.QueryRecordArtifacts
}

///|
fn build_duckdb_broad_records(
  authority : DuckDBBroadAuthority,
  retained : DuckDBBroadRetention,
  limits : @planning.QueryMaterialLimits,
) -> Result[DuckDBBroadRecords, DuckDBEvidenceIssue] {
  if limits.max_work < 0 ||
    limits.max_fields < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let requirement = retained.preparation.requirement
  let query = @query.query_sequence_requirement(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
  )
  guard @pipeline.schema_at(
      @sourcequery.query_acquisition_pipeline(query),
      @sourcequery.query_acquisition_input(query),
    )
    is Some(schema) else {
    return Err(InvalidRetainedLayout)
  }
  @planning.build_query_record_artifacts(
    requirement,
    retained.measured.scan,
    retained.measured.output,
    schema,
    authority.issuer.name,
    authority.number,
    limits,
  )
  .map(artifacts => { authority, retention: retained, artifacts, })
  .map_err(duckdb_artifact_issue)
}

///|
pub fn issue_duckdb_broad_records(
  attempt : DuckDBBroadAttempt,
  limits : @planning.QueryMaterialLimits,
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
  @planning.query_record_artifact_at(records.artifacts, index)
}

///|
fn duckdb_artifact_issue(
  issue : @planning.QueryArtifactIssue,
) -> DuckDBEvidenceIssue {
  match issue {
    InvalidLimits => InvalidLimits
    InvalidRetainedLayout => InvalidRetainedLayout
    FieldLimit => FieldLimit
    WorkLimit => WorkLimit
    ForeignMaterial => ForeignRecords
    Encoding(issue) => Encoding(issue)
  }
}
