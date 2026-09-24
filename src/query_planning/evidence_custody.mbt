///|
/// Trusted Host registration fixes the evidence contract, requirement and
/// physical settlement verifier before an attempt can execute.
pub struct QueryEvidenceRegistration[A] {
  _contracts : QueryEvidenceContracts
  requirement : QueryRequirement
  name : String
  attempts : IssuerCounter
  mut live : Bool
  mut transport_matches : (A) -> Bool
}

///|
pub struct QueryEvidenceAttemptAuthority[A] {
  registration : QueryEvidenceRegistration[A]
  number : String
}

///|
let query_evidence_registration_serial : IssuerCounter = issuer_counter()

///|
/// The registration and attempt authority are not CIDs or wire grants.
pub fn[A] register_query_evidence_issuer(
  contracts : QueryEvidenceContracts,
  requirement : QueryRequirement,
  process_nonce : String,
  max_nonce_chars : Int,
  issuer_kind : String,
  transport_matches : (A) -> Bool,
) -> Result[QueryEvidenceRegistration[A], QueryEvidenceCustodyIssue] {
  if max_nonce_chars < 0 {
    return Err(InvalidLimits)
  }
  if process_nonce.is_empty() ||
    process_nonce.length() > max_nonce_chars ||
    issuer_kind.is_empty() {
    return Err(InvalidIdentity)
  }
  guard reserve_issuer_number(query_evidence_registration_serial)
    is Some(serial) else {
    return Err(IdentifierExhausted)
  }
  Ok({
    _contracts: contracts,
    requirement,
    name: process_nonce + "/" + issuer_kind + "/" + serial.to_string(),
    attempts: issuer_counter(),
    live: true,
    transport_matches,
  })
}

///|
pub fn[A] query_evidence_registration_name(
  registration : QueryEvidenceRegistration[A],
) -> String {
  registration.name
}

///|
pub fn[A] query_evidence_registration_requirement(
  registration : QueryEvidenceRegistration[A],
) -> QueryRequirement {
  registration.requirement
}

///|
pub fn[A] query_evidence_registration_live(
  registration : QueryEvidenceRegistration[A],
) -> Bool {
  registration.live
}

///|
pub fn[A] query_evidence_transport_matches(
  registration : QueryEvidenceRegistration[A],
  attempt : A,
) -> Bool {
  registration.live && (registration.transport_matches)(attempt)
}

///|
pub fn[A] close_query_evidence_registration(
  registration : QueryEvidenceRegistration[A],
) -> Unit {
  registration.live = false
  registration.transport_matches = _ => false
}

///|
fn[A] reserve_query_evidence_attempt_authority(
  registration : QueryEvidenceRegistration[A],
) -> Result[QueryEvidenceAttemptAuthority[A], QueryEvidenceCustodyIssue] {
  if !registration.live {
    return Err(IssuerClosed)
  }
  guard reserve_issuer_number(registration.attempts) is Some(number) else {
    return Err(IdentifierExhausted)
  }
  Ok({ registration, number: number.to_string(), })
}

///|
/// Selection and issuer authority are bound before provider execution. The
/// provider supplies only the requirement accessor for its opaque preparation.
pub fn[A, P] reserve_selected_query_evidence_attempt(
  registration : QueryEvidenceRegistration[A],
  choice : AcquisitionChoice,
  candidate : PreparedAcquisition[P],
  requirement_of : (P) -> QueryRequirement,
) -> Result[(P, QueryEvidenceAttemptAuthority[A]), QueryEvidenceCustodyIssue] {
  if !registration.live {
    return Err(IssuerClosed)
  }
  guard acquisition_choice_payload(choice, candidate) is Some(preparation) else {
    return Err(NotSelected)
  }
  if !physical_equal(registration.requirement, requirement_of(preparation)) {
    return Err(ForeignRequirement)
  }
  reserve_query_evidence_attempt_authority(registration).map(authority => {
    (preparation, authority)
  })
}

///|
pub fn[A] query_evidence_attempt_number(
  authority : QueryEvidenceAttemptAuthority[A],
) -> String {
  authority.number
}

///|
/// This owner is local to one retained acquisition attempt. Connector-specific
/// execution remains outside it, but record issuance and capture cannot be
/// reconstructed from a CID or a successful transport status.
struct QueryEvidenceCustody[I, A, R] {
  registration : QueryEvidenceRegistration[A]
  authority : QueryEvidenceAttemptAuthority[A]
  issuer : I
  attempt : A
  retention : R
  measured : MeasuredQueryRows
  scan : @execution.CapturedRows
  output : @execution.CompletedOutput
  mut issued : QueryEvidenceIssued[I, A, R]?
  mut captured : QueryEvidenceCaptured[I, A, R]?
}

///|
pub struct QueryEvidenceIssued[I, A, R] {
  owner : QueryEvidenceCustody[I, A, R]
  artifacts : QueryRecordArtifacts
}

///|
pub struct QueryEvidenceCaptured[I, A, R] {
  issued : QueryEvidenceIssued[I, A, R]
  document : @encode.EncodedDocument
  cid : String
  bytes : Int
  nodes : Int
}

///|
pub(all) enum QueryEvidenceCustodyIssue {
  InvalidLimits
  InvalidIdentity
  IdentifierExhausted
  IssuerClosed
  NotSelected
  ForeignRequirement
  ForeignOwner
  ForeignRetention
  UnverifiedTransport
  ForeignRecords
  AlreadyCaptured
  Artifact(QueryArtifactIssue)
}

///|
fn[I, A, R] verify_custody_owner(
  owner : QueryEvidenceCustody[I, A, R],
  registration : QueryEvidenceRegistration[A],
  authority : QueryEvidenceAttemptAuthority[A],
  issuer : I,
  attempt : A,
  retention : R,
) -> Result[Unit, QueryEvidenceCustodyIssue] {
  if !registration.live {
    return Err(IssuerClosed)
  }
  if !physical_equal(owner.registration, registration) ||
    !physical_equal(owner.authority, authority) ||
    !physical_equal(authority.registration, registration) ||
    !physical_equal(owner.issuer, issuer) ||
    !physical_equal(owner.attempt, attempt) {
    return Err(ForeignOwner)
  }
  if !physical_equal(owner.retention, retention) ||
    !@execution.row_wire_matches_captured(owner.measured.scan, owner.scan) ||
    !@execution.row_wire_matches_output(owner.measured.output, owner.output) {
    return Err(ForeignRetention)
  }
  if !(registration.transport_matches)(attempt) {
    return Err(UnverifiedTransport)
  }
  Ok(())
}

///|
pub fn[I, A, R] issue_query_evidence(
  registration : QueryEvidenceRegistration[A],
  authority : QueryEvidenceAttemptAuthority[A],
  issuer : I,
  attempt : A,
  retention : R,
  measured : MeasuredQueryRows,
  scan : @execution.CapturedRows,
  output : @execution.CompletedOutput,
  schema : @schema.Schema,
  limits : QueryMaterialLimits,
) -> Result[QueryEvidenceIssued[I, A, R], QueryEvidenceCustodyIssue] {
  let owner : QueryEvidenceCustody[I, A, R] = {
    registration,
    authority,
    issuer,
    attempt,
    retention,
    measured,
    scan,
    output,
    issued: None,
    captured: None,
  }
  match
    verify_custody_owner(
      owner, registration, authority, issuer, attempt, retention,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let artifacts = match
    build_query_record_artifacts(
      registration.requirement,
      measured.scan,
      measured.output,
      schema,
      registration.name,
      authority.number,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Artifact(issue))
  }
  let issued = { owner, artifacts, }
  owner.issued = Some(issued)
  Ok(issued)
}

///|
pub fn[I, A, R] verify_query_evidence_issued(
  issued : QueryEvidenceIssued[I, A, R],
  registration : QueryEvidenceRegistration[A],
  authority : QueryEvidenceAttemptAuthority[A],
  issuer : I,
  attempt : A,
  retention : R,
) -> Result[Unit, QueryEvidenceCustodyIssue] {
  let owner = issued.owner
  match
    verify_custody_owner(
      owner, registration, authority, issuer, attempt, retention,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard owner.issued is Some(actual) &&
    physical_equal(actual, issued) &&
    physical_equal(issued.artifacts.requirement, registration.requirement) else {
    return Err(ForeignRecords)
  }
  Ok(())
}

///|
pub fn[I, A, R] capture_query_evidence(
  issued : QueryEvidenceIssued[I, A, R],
  registration : QueryEvidenceRegistration[A],
  authority : QueryEvidenceAttemptAuthority[A],
  issuer : I,
  attempt : A,
  retention : R,
  limits : QueryEvidenceLimits,
) -> Result[QueryEvidenceCaptured[I, A, R], QueryEvidenceCustodyIssue] {
  match
    verify_query_evidence_issued(
      issued, registration, authority, issuer, attempt, retention,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if issued.owner.captured is Some(_) {
    return Err(AlreadyCaptured)
  }
  let (document, cid, bytes, nodes) = match
    build_query_observation_artifact(issued.artifacts, limits) {
    Ok(value) => value
    Err(issue) => return Err(Artifact(issue))
  }
  let captured = { issued, document, cid, bytes, nodes, }
  issued.owner.captured = Some(captured)
  Ok(captured)
}

///|
pub fn[I, A, R] verify_query_evidence_captured(
  captured : QueryEvidenceCaptured[I, A, R],
  registration : QueryEvidenceRegistration[A],
  authority : QueryEvidenceAttemptAuthority[A],
  issuer : I,
  attempt : A,
  retention : R,
) -> Result[Unit, QueryEvidenceCustodyIssue] {
  match
    verify_query_evidence_issued(
      captured.issued,
      registration,
      authority,
      issuer,
      attempt,
      retention,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard captured.issued.owner.captured is Some(actual) &&
    physical_equal(actual, captured) else {
    return Err(ForeignRecords)
  }
  Ok(())
}

///|
pub(all) enum QueryEvidenceConsumerIssue {
  Evidence(QueryEvidenceCustodyIssue)
  ForeignObservation
  Consumer(@execution.ProducerBindingIssue)
}

///|
/// Bind a consumer to the exact captured evidence owner. Provider-specific
/// execution can revoke its observation through `state_live`, while the common
/// owner rechecks issuer, transport settlement and retained output on every
/// read. Neither a record CID nor a provider-supplied output can replace it.
pub fn[I, A, R] bind_captured_query_evidence_input(
  captured : QueryEvidenceCaptured[I, A, R],
  issued : QueryEvidenceIssued[I, A, R],
  registration : QueryEvidenceRegistration[A],
  authority : QueryEvidenceAttemptAuthority[A],
  issuer : I,
  attempt : A,
  retention : R,
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
  state_live : () -> Bool,
) -> Result[@execution.BoundProducerInput, QueryEvidenceConsumerIssue] {
  if !physical_equal(captured.issued, issued) {
    return Err(ForeignObservation)
  }
  match
    verify_query_evidence_captured(
      captured, registration, authority, issuer, attempt, retention,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Evidence(issue))
  }
  if !state_live() {
    return Err(ForeignObservation)
  }
  @execution.bind_live_completed_input(
    receiver,
    input_index,
    expected_producer,
    captured.issued.owner.output,
    fn() {
      state_live() &&
      verify_query_evidence_captured(
        captured, registration, authority, issuer, attempt, retention,
      )
      is Ok(_)
    },
  ).map_err(issue => Consumer(issue))
}

///|
pub fn[I, A, R] query_evidence_record_at(
  issued : QueryEvidenceIssued[I, A, R],
  index : Int,
) -> (@encode.EncodedDocument, String)? {
  query_record_artifact_at(issued.artifacts, index)
}

///|
pub fn[I, A, R] query_evidence_capture_document(
  captured : QueryEvidenceCaptured[I, A, R],
) -> @encode.EncodedDocument {
  captured.document
}

///|
pub fn[I, A, R] query_evidence_capture_cid(
  captured : QueryEvidenceCaptured[I, A, R],
) -> String {
  captured.cid
}

///|
pub fn[I, A, R] query_evidence_capture_usage(
  captured : QueryEvidenceCaptured[I, A, R],
) -> (Int, Int) {
  (captured.bytes, captured.nodes)
}
