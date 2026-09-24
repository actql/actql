///|
/// Trusted Host registration, not a Connector wire authority. The callback
/// verifies exact grant/port/read-view/settled transport ownership outside this
/// package. It must never accept a CID, path, SQL-success bool or JSON as proof.
struct DuckDBQueryIssuer {
  registration : @planning.QueryEvidenceRegistration[DuckDBBroadAttempt]
}

///|
priv struct DuckDBBroadAuthority {
  issuer : DuckDBQueryIssuer
  token : @planning.QueryEvidenceAttemptAuthority[DuckDBBroadAttempt]
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
  @planning.register_query_evidence_issuer(
    contracts, requirement, process_nonce, max_nonce_chars, "duckdb-issuer", transport_matches,
  )
  .map(registration => { registration, })
  .map_err(duckdb_custody_issue)
}

///|
/// Bind selection and issuer before metadata/row access. No operation attaches
/// authority to an already executed unissued attempt.
pub fn prepare_issued_duckdb_broad_attempt(
  issuer : DuckDBQueryIssuer,
  choice : @planning.AcquisitionChoice,
  prepared : @planning.PreparedAcquisition[DuckDBQueryPreparation],
) -> Result[DuckDBBroadAttempt, DuckDBEvidenceIssue] {
  let (preparation, token) = match
    @planning.reserve_selected_query_evidence_attempt(
      issuer.registration,
      choice,
      prepared,
      preparation => preparation.requirement,
    ) {
    Ok(value) => value
    Err(issue) => return Err(duckdb_custody_issue(issue))
  }
  let attempt = prepare_duckdb_broad_attempt(preparation)
  Ok({ ..attempt, authority: Some({ issuer, token, }), })
}

///|
pub fn close_duckdb_query_issuer(issuer : DuckDBQueryIssuer) -> Unit {
  @planning.close_query_evidence_registration(issuer.registration)
}

///|
pub fn duckdb_broad_attempt_identity(
  attempt : DuckDBBroadAttempt,
) -> (String, String)? {
  attempt.authority.map(value => {
    (
      @planning.query_evidence_registration_name(value.issuer.registration),
      @planning.query_evidence_attempt_number(value.token),
    )
  })
}

///|
struct DuckDBBroadRecords {
  authority : DuckDBBroadAuthority
  retention : DuckDBBroadRetention
  issued : @planning.QueryEvidenceIssued[
    DuckDBQueryIssuer,
    DuckDBBroadAttempt,
    DuckDBBroadRetention,
  ]
}

///|
fn build_duckdb_broad_records(
  authority : DuckDBBroadAuthority,
  attempt : DuckDBBroadAttempt,
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
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let query = @query.query_sequence_requirement(sequence)
  guard @lower.preparation_schema_at(
      @lower.bound_preparation(@query.query_sequence_owner(sequence)),
      @sourcequery.query_acquisition_input(query),
    )
    is Some(schema) else {
    return Err(InvalidRetainedLayout)
  }
  @planning.issue_query_evidence(
    authority.issuer.registration,
    authority.token,
    authority.issuer,
    attempt,
    retained,
    retained.measured,
    retained.completion._scan,
    retained.output,
    schema,
    limits,
  )
  .map(issued => { authority, retention: retained, issued, })
  .map_err(duckdb_custody_issue)
}

///|
pub fn issue_duckdb_broad_records(
  attempt : DuckDBBroadAttempt,
  limits : @planning.QueryMaterialLimits,
) -> Result[DuckDBBroadRecords, DuckDBEvidenceIssue] {
  guard attempt.authority is Some(authority) else {
    return Err(UnauthorizedAttempt)
  }
  if !@planning.query_evidence_registration_live(authority.issuer.registration) {
    return Err(IssuerClosed)
  }
  guard attempt.state is Retained(retained) else { return Err(NotRetained) }
  if !physical_equal(
      @planning.query_evidence_registration_requirement(
        authority.issuer.registration,
      ),
      retained.preparation.requirement,
    ) ||
    !duckdb_broad_retention_matches(retained, attempt) {
    abort_duckdb_broad_attempt(attempt)
    return Err(UnauthorizedAttempt)
  }
  match build_duckdb_broad_records(authority, attempt, retained, limits) {
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
  if !@planning.query_evidence_registration_live(issuer.registration) {
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
      @planning.query_evidence_registration_requirement(issuer.registration),
      records.retention.preparation.requirement,
    ) else {
    return Err(ForeignRecords)
  }
  match
    @planning.verify_query_evidence_issued(
      records.issued,
      issuer.registration,
      records.authority.token,
      issuer,
      attempt,
      records.retention,
    ) {
    Ok(_) => Ok(())
    Err(issue) => Err(duckdb_custody_issue(issue))
  }
}

///|
pub fn duckdb_broad_record_at(
  records : DuckDBBroadRecords,
  index : Int,
) -> (@encode.EncodedDocument, String)? {
  @planning.query_evidence_record_at(records.issued, index)
}

///|
fn duckdb_custody_issue(
  issue : @planning.QueryEvidenceCustodyIssue,
) -> DuckDBEvidenceIssue {
  match issue {
    InvalidLimits => InvalidLimits
    InvalidIdentity => IdentifierLimit
    IdentifierExhausted => IdentifierExhausted
    IssuerClosed => IssuerClosed
    NotSelected => NotSelected
    ForeignRequirement => UnauthorizedAttempt
    ForeignOwner => UnauthorizedAttempt
    ForeignRetention | ForeignRecords => ForeignRecords
    UnverifiedTransport => UnverifiedTransport
    AlreadyCaptured => AlreadyCaptured
    Artifact(issue) => duckdb_artifact_issue(issue)
  }
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
