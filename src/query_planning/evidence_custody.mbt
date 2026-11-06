///|
/// Trusted Host registration fixes the evidence contract, requirement and
/// physical settlement verifier before an attempt can execute.
/// Keep the original checked profile and requirement types. Selection and
/// attempt numbering are shared; Direct receipt issuance below still requires
/// the exact QueryEvidenceContracts/QueryRequirement pair.
pub struct QueryEvidenceRegistration[C, Q, A] {
  _contracts : C
  requirement : Q
  name : String
  attempts : IssuerCounter
  mut live : Bool
  mut transport_matches : (A) -> Bool
}

///|
pub struct QueryEvidenceAttemptAuthority[C, Q, A] {
  registration : QueryEvidenceRegistration[C, Q, A]
  number : String
}

///|
let query_evidence_registration_serial : IssuerCounter = issuer_counter()

///|
/// The registration and attempt authority are not CIDs or wire grants.
pub fn[C, Q, A] register_query_evidence_issuer(
  contracts : C,
  requirement : Q,
  process_nonce : String,
  max_nonce_chars : Int,
  issuer_kind : String,
  transport_matches : (A) -> Bool,
) -> Result[QueryEvidenceRegistration[C, Q, A], QueryEvidenceCustodyIssue] {
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
pub fn[C, Q, A] query_evidence_registration_name(
  registration : QueryEvidenceRegistration[C, Q, A],
) -> String {
  registration.name
}

///|
pub fn[C, Q, A] query_evidence_registration_requirement(
  registration : QueryEvidenceRegistration[C, Q, A],
) -> Q {
  registration.requirement
}

///|
pub fn[C, Q, A] query_evidence_registration_live(
  registration : QueryEvidenceRegistration[C, Q, A],
) -> Bool {
  registration.live
}

///|
pub fn[C, Q, A] query_evidence_transport_matches(
  registration : QueryEvidenceRegistration[C, Q, A],
  attempt : A,
) -> Bool {
  registration.live && (registration.transport_matches)(attempt)
}

///|
pub fn[C, Q, A] close_query_evidence_registration(
  registration : QueryEvidenceRegistration[C, Q, A],
) -> Unit {
  registration.live = false
  registration.transport_matches = _ => false
}

///|
fn[C, Q, A] reserve_query_evidence_attempt_authority(
  registration : QueryEvidenceRegistration[C, Q, A],
) -> Result[QueryEvidenceAttemptAuthority[C, Q, A], QueryEvidenceCustodyIssue] {
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
pub fn[C, Q, A, P] reserve_selected_query_evidence_attempt(
  registration : QueryEvidenceRegistration[C, Q, A],
  choice : AcquisitionChoice[Q],
  candidate : PreparedAcquisition[Q, P],
  requirement_of : (P) -> Q,
) -> Result[
  (P, QueryEvidenceAttemptAuthority[C, Q, A]),
  QueryEvidenceCustodyIssue,
] {
  if !registration.live {
    return Err(IssuerClosed)
  }
  guard acquisition_choice_payload(choice, candidate) is Some(preparation) else {
    return Err(NotSelected)
  }
  if !physical_equal(registration.requirement, candidate.candidate.requirement) ||
    !physical_equal(registration.requirement, requirement_of(preparation)) {
    return Err(ForeignRequirement)
  }
  reserve_query_evidence_attempt_authority(registration).map(authority => {
    (preparation, authority)
  })
}

///|
pub fn[C, Q, A] query_evidence_attempt_number(
  authority : QueryEvidenceAttemptAuthority[C, Q, A],
) -> String {
  authority.number
}

///|
pub fn[C, Q, A] query_evidence_attempt_matches_registration(
  authority : QueryEvidenceAttemptAuthority[C, Q, A],
  registration : QueryEvidenceRegistration[C, Q, A],
) -> Bool {
  registration.live && physical_equal(authority.registration, registration)
}

///|
/// This owner is local to one retained acquisition attempt. Connector-specific
/// execution remains outside it, but record issuance and capture cannot be
/// reconstructed from a CID or a successful transport status.
struct QueryEvidenceCustody[I, A, R] {
  registration : QueryEvidenceRegistration[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ]
  authority : QueryEvidenceAttemptAuthority[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ]
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
/// Retire only the original custody's reciprocal references. An issued set
/// without a capture may be abandoned; a successful capture must first lose
/// its original registration. This is not transport cleanup or allocation
/// acknowledgement. Escaped records and observations retain immutable DATA.
/// A rejected retirement leaves every reference intact; success is idempotent.
pub fn[I, A, R] retire_query_evidence_custody(
  issued : QueryEvidenceIssued[I, A, R],
) -> Bool {
  let owner = issued.owner
  match owner.issued {
    None => return owner.captured is None
    Some(original) => if !physical_equal(original, issued) { return false }
  }
  if owner.captured is Some(_) && owner.registration.live {
    return false
  }
  owner.captured = None
  owner.issued = None
  true
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
  registration : QueryEvidenceRegistration[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
  authority : QueryEvidenceAttemptAuthority[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
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
  registration : QueryEvidenceRegistration[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
  authority : QueryEvidenceAttemptAuthority[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
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
  registration : QueryEvidenceRegistration[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
  authority : QueryEvidenceAttemptAuthority[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
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
  registration : QueryEvidenceRegistration[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
  authority : QueryEvidenceAttemptAuthority[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
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
  registration : QueryEvidenceRegistration[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
  authority : QueryEvidenceAttemptAuthority[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
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
  registration : QueryEvidenceRegistration[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
  authority : QueryEvidenceAttemptAuthority[
    QueryEvidenceContracts,
    QueryRequirement,
    A,
  ],
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
