///|
/// Existing finite Host-attestation grant and its one-use candidate. This
/// object does not acknowledge either physical write or permission to sign.
pub struct ClientEffectHostAttestationUse {
  attestation : ClientEffectResolutionAttestationOriginal
  grant : @credential.LocalSigningCredentialGrant
  use_entry : @credential.LocalSigningCredentialUse
}

///|
/// Current physical signing role adopted on first installation. The Host
/// has already joined its operator's exact selected file and key generation.
pub(all) struct ClientEffectSelectedHostSigningOriginal {
  account : @authorization.AdmittedAccountConfiguration
  principal : String
  connection : String
  resource : String
  authority_scope_cid : String
  adoption_cid : String
  initialization_intent_cid : String
  key_configuration_cid : String
  key_generation_cid : String
  key_id : String
  key_public : String
}

///|
/// Borrow the original authenticated computation and invocation. The
/// constructor runs under the existing bounded Resolve Read; callers fund
/// the same capture/Result forest before any property escapes.
pub fn ClientEffectResolutionAttestationOriginal::restore_computation(
  self : ClientEffectResolutionAttestationOriginal,
  limits : @checkpoint.WireLimits,
  fund : (Int, Int, Int) -> Bool,
  work : (Int) -> Bool,
) -> Result[ClientEffectSavedComputation, ClientCheckpointJournalIssue] {
  restore_client_effect_saved_computation(
    self.review.reference,
    self.review.captured,
    limits,
    fund,
    work,
  )
}

///|
/// Construct the HostAttestation scope from the same confirmed signed answer,
/// the sealed capture's checked invocation and unit. It evaluates the current
/// adopted Account for this exact signing subject in addition to run:resolve.
pub fn ClientEffectResolutionAttestationOriginal::prepare_use(
  self : ClientEffectResolutionAttestationOriginal,
  selected : ClientEffectSelectedHostSigningOriginal,
  sampled_at : Int64,
  current : () -> Bool,
) -> Result[ClientEffectHostAttestationUse, ClientEffectResolutionOriginalIssue] {
  let sign : @authorization.AccessTuple = {
    principal: selected.principal,
    connection: selected.connection,
    resource: selected.resource,
    operation: "sign",
  }
  let resolve = { ..sign, resource: "run", operation: "resolve", }
  let waiting = self.review.reference.waiting
  let artifact = waiting.checkpoint.artifact
  let checkpoint = artifact.checkpoint
  let request = waiting.run.request
  let definition = waiting.run.definition
  let definition_id = @publication.publication_contract_identity(definition)
  let submitted = client_saved_submission_record(waiting.submission)
  let submission_id = client_submission_reference_record_request_id(
    submitted.reference,
  )
  guard current() &&
    selected.resource == "key/initial-host-attestation" &&
    @authorization.evaluate_account(selected.account, resolve)
    is @authorization.Allow(_) &&
    @authorization.evaluate_account(selected.account, sign)
    is @authorization.Allow(_) &&
    @values.timestamp_epoch_milliseconds(self.at) == Some(sampled_at) &&
    @values.timestamp_epoch_milliseconds(checkpoint.expires_at)
    is Some(checkpoint_expiry) &&
    selected.authority_scope_cid == client_request_authority_scope_cid(request) &&
    submission_id == client_request_caller_id(request) &&
    self.review.reference.unit_definition_cid is Some(unit_id) &&
    valid_client_request_cid(self.review.reference.preview.invocation_cid) else {
    return Err(InvalidOriginal)
  }
  let lines = selected.key_public.trim().split("\n").collect()
  guard lines.length() == 3 &&
    lines[0] == "-----BEGIN PUBLIC KEY-----" &&
    lines[2] == "-----END PUBLIC KEY-----" else {
    return Err(InvalidOriginal)
  }
  let der = @base64.decode(lines[1][:]) catch {
    _ => return Err(InvalidOriginal)
  }
  guard der.length() == 44 &&
    @base64.encode(der)[:] == lines[1] &&
    der[:12] == b"\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00"[:] &&
    @credential.prepare_local_signing_public_key(der[12:].to_owned())
    is Ok(key_public) else {
    return Err(InvalidOriginal)
  }
  let scope : @credential.LocalSigningCredentialScope = {
    account_configuration_cid: @authorization.account_configuration_cid(
      selected.account,
    ),
    account_id: selected.account.account_id(),
    attempt_id: self.admitted.resolution_cid,
    authority_scope_cid: client_request_authority_scope_cid(request),
    checkpoint_cid: artifact.checkpoint_cid,
    checkpoint_id: checkpoint.checkpoint_id,
    checkpoint_kind: checkpoint.kind,
    host_adoption_cid: selected.adoption_cid,
    key_configuration_cid: selected.key_configuration_cid,
    key_generation_cid: selected.key_generation_cid,
    key_id: selected.key_id,
    key_public_key_cid: key_public.cid(),
    preimage: self.admitted.attestation_preimage,
    principal: selected.principal,
    request_cid: client_request_intent_cid(request),
    request_scope_cid: client_request_scope_cid(request),
    run_definition_cid: definition_id,
    run_invocation_cid: self.review.reference.preview.invocation_cid,
    submission_scope_cid: submission_id,
    unit_definition_cid: unit_id,
    purpose: @credential.HostAttestation,
  }
  let policy = client_local_default_signing_bootstrap_policy()
  guard policy.issuer_identity(selected.initialization_intent_cid) is Ok(issuer) &&
    policy.prepare_first_issue(sampled_at, Some(checkpoint_expiry))
    is Ok(issued) &&
    @credential.prepare_local_signing_credential_grant(
      issuer,
      scope,
      issued.expires_at(),
      policy.max_uses(),
    )
    is Ok(grant) &&
    @credential.prepare_local_signing_credential_use(
      grant,
      self.admitted.resolution_cid,
      sampled_at,
      0,
      false,
      scope,
    )
    is Ok(use_entry) &&
    current() else {
    return Err(InvalidOriginal)
  }
  Ok({ attestation: self, grant, use_entry, })
}

///|
/// Export the existing credential scope's canonical identities/body and the
/// exact unsigned Host preimage. The same adopted writer must verify absence
/// and compare-exchange the original use, then confirm it under a fresh Read.
pub fn ClientEffectHostAttestationUse::originals(
  self : ClientEffectHostAttestationUse,
) -> Result[
  (String, String, String, String, String),
  ClientEffectResolutionOriginalIssue,
] {
  guard @credential.local_signing_credential_grant_json(self.grant) is Ok(grant) &&
    @credential.local_signing_credential_use_json(self.use_entry)
    is Ok(use_entry) else {
    return Err(Encoding)
  }
  Ok(
    (
      @credential.local_signing_credential_grant_cid(self.grant),
      grant,
      @credential.local_signing_credential_use_cid(self.use_entry),
      use_entry,
      self.attestation.attestation_preimage(),
    ),
  )
}

///|
pub fn ClientEffectHostAttestationUse::checkpoint_cid(
  self : ClientEffectHostAttestationUse,
) -> String {
  @credential.local_signing_credential_grant_scope(self.grant).checkpoint_cid
}

///|
pub fn ClientEffectResolutionAttestationOriginal::observed_at_ms(
  self : ClientEffectResolutionAttestationOriginal,
) -> Int64? {
  @values.timestamp_epoch_milliseconds(self.at)
}

///|
pub fn ClientEffectHostAttestationUse::window(
  self : ClientEffectHostAttestationUse,
) -> (Int64, Int64)? {
  let (_, expiry) = @credential.local_signing_credential_grant_limits(
    self.grant,
  )
  self.attestation.observed_at_ms().map(now => (now, expiry))
}

///|
/// The same Host role may seal this confirmed use's chosen original only.
pub fn ClientEffectHostAttestationUse::prepare_decision(
  self : ClientEffectHostAttestationUse,
  signature : String,
  current : () -> Bool,
  limits : @checkpoint.WireLimits,
  before_decode : (ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ],
  before_encode : (Int, Int, Int) -> Result[Unit, ClientJournalEncodingIssue],
) -> Result[
  ClientEffectResolutionJournalDecision,
  ClientEffectResolutionOriginalIssue,
] {
  let scope = @credential.local_signing_credential_grant_scope(self.grant)
  if scope.purpose != @credential.HostAttestation ||
    scope.preimage != self.attestation.attestation_preimage() {
    return Err(InvalidOriginal)
  }
  self.attestation.prepare_journal_decision(
    scope.key_id,
    signature,
    current,
    limits,
    before_decode=Some(before_decode),
    before_encode=Some(before_encode),
  )
}

///|
/// Candidate coordinates for trusted physical transfer. Public disclosure
/// still requires the independent returned successor observation.
pub fn ClientEffectResolutionJournalDecision::candidate_coordinates(
  self : ClientEffectResolutionJournalDecision,
) -> (String, String, Bool) {
  (
    self.verified.checkpoint_cid,
    self.verified.resolution_cid,
    self.verified.decision == @checkpoint.Approved,
  )
}
