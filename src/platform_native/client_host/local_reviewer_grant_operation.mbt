///|
// Existing Host/Credential assembly only. The original paired subject is held
// as an opaque read reference, not rebuilt from this operation's CID strings.
struct NativeLocalReviewerSigningGrantOperation {
  materials : NativeLocalReviewerProofMaterials
  key : NativeLocalSigningKeyOriginal
  subject : NativeLocalOriginalEffectSigningSubjectRead
  issuer_file : NativeLocalSelectedFile
  original : NativeLocalGrantOriginal
}

///|
// Confirmation of one immutable original append, not a signing use, exact
// signature, Resolution acceptance or permission derived from a stored Allow.
struct NativeLocalReviewerSigningGrantAcknowledgement {
  operation : NativeLocalReviewerSigningGrantOperation
}

///|
pub(all) enum NativeLocalReviewerSigningGrantIssue {
  SigningGrantUnavailable
  SigningGrantMaterials(NativeLocalReviewerProofMaterialsIssue)
  SigningGrantIssuer(NativeLocalCredentialIssuerIssue)
  SigningGrantJournal(NativeClientRunJournalIssue)
  SigningGrantMetadata(@credential.RemoteCredentialIssue)
  SigningGrantHistory(NativeLocalSigningHistoryIssue)
}

///|
fn NativeLocalReviewerSigningGrantOperation::require_current(
  self : NativeLocalReviewerSigningGrantOperation,
) -> Result[Unit, NativeLocalReviewerSigningGrantIssue] {
  guard self.original.grant is SigningGrant(grant) else {
    return Err(SigningGrantUnavailable)
  }
  let host = self.key.account.host
  match host.selected_configuration(self.issuer_file.name) {
    Ok(body) if body == self.issuer_file.body &&
      self.issuer_file.content_cid == self.original.issuer_selection_cid => ()
    _ => return Err(SigningGrantUnavailable)
  }
  match
    self.materials.require_original_signing_scope(
      @credential.local_signing_credential_grant_scope(grant),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(SigningGrantMaterials(issue))
  }
  // The last current/clock callbacks above may retire the capture. No callback
  // follows the same original references' terminal lifetime comparison.
  let scope = @credential.local_signing_credential_grant_scope(grant)
  match self.subject.original_subject_after_current() {
    Ok((invocation, unit)) if invocation == scope.run_invocation_cid &&
      unit == scope.unit_definition_cid => Ok(())
    _ => Err(SigningGrantUnavailable)
  }
}

///|
/// Prepare one explicit operation from the original paired Checkpoint, Client
/// Submission and selected key. The issuer may be a different principal. Its
/// selected finite metadata does not obtain issue permission or write a row.
pub fn NativeLocalReviewerProofMaterials::prepare_signing_grant_operation(
  self : NativeLocalReviewerProofMaterials,
  issuer_file_name : String,
  operation_id : String,
  attempt_id : String,
) -> Result[
  NativeLocalReviewerSigningGrantOperation,
  NativeLocalReviewerSigningGrantIssue,
] {
  // The explicit issuer-file route retains its configured source-root key.
  // An initialized Store key cannot acquire that authority by relabelling it.
  guard self.key is ConfiguredReviewerKey(key) else {
    return Err(SigningGrantUnavailable)
  }
  let scope = match self.prepare_signing_scope(attempt_id) {
    Ok(value) => value
    Err(issue) => return Err(SigningGrantMaterials(issue))
  }
  let host = key.account.host
  guard host.session.settings.files
    .iter()
    .find_first(file => file.name == issuer_file_name)
    is Some(issuer_file) else {
    return Err(SigningGrantUnavailable)
  }
  let selected = match host.selected_configuration(issuer_file.name) {
    Ok(body) if body == issuer_file.body => body
    _ => return Err(SigningGrantUnavailable)
  }
  let wire = @utf8.decode(selected) catch {
    _ => return Err(SigningGrantUnavailable)
  }
  let selection = match admit_native_local_credential_issuer_selection(wire) {
    Ok(value) => value
    Err(issue) => return Err(SigningGrantIssuer(issue))
  }
  if !selection.enabled {
    return Err(SigningGrantIssuer(Disabled))
  }
  let grant = match
    @credential.prepare_local_signing_credential_grant(
      selection.issuer_authority,
      scope,
      @values.timestamp_epoch_milliseconds(selection.expires_at).unwrap(),
      selection.max_uses,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SigningGrantMetadata(issue))
  }
  let original = match
    local_owned_grant_original(
      key.account.crypto,
      operation_id,
      self.reviewer.request,
      issuer_file.content_cid,
      SigningGrant(grant),
    ) {
    Ok(value) => value
    Err(issue) => return Err(SigningGrantJournal(issue))
  }
  let subject = match
    self.reviewer.approval_scope.read_original_signing_subject_for(
      self.reviewer.request,
      self.reviewer.original.run_definition_cid,
      self.original.artifact.checkpoint_cid,
    ) {
    Ok(value) => value
    Err(_) => return Err(SigningGrantUnavailable)
  }
  let operation : NativeLocalReviewerSigningGrantOperation = {
    materials: self,
    key,
    subject,
    issuer_file,
    original,
  }
  operation.require_current().map(_ => operation)
}

///|
// Current actual issuer and purpose gates remain distinct. Do not invoke the
// outer transactional readers here: this is already the original journal TX.
fn NativeLocalReviewerSigningGrantOperation::require_current_locked(
  self : NativeLocalReviewerSigningGrantOperation,
  issuer : NativeLocalCredentialIssuerBinding,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let materials = self.materials
  let key = self.key
  let host = key.account.host
  if !physical_equal(issuer.host, host) ||
    issuer.file.name != self.issuer_file.name ||
    issuer.file.body != self.issuer_file.body ||
    issuer.file.content_cid != self.issuer_file.content_cid ||
    issuer.file.generation != self.issuer_file.generation ||
    issuer.operation_cid != self.original.operation_cid ||
    !local_original_grant_matches_issuer(self.original.grant, issuer.selection) {
    return Err(ChangedIntent)
  }
  guard self.original.grant is SigningGrant(grant) else {
    return Err(AuthorizationDenied)
  }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  match issuer.require_current(host, self.original.operation_cid) {
    Ok(_) => ()
    Err(_) => return Err(AuthorizationDenied)
  }
  let authority = match
    native_local_policy_authority_for(
      host,
      key.account.crypto,
      materials.reviewer.principal,
      materials.reviewer.connection,
      self.original.request,
      ReadRunMaterials,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !authority.current_for(host.journal, self.original.request) ||
    key.account.require_current_account() is Err(_) ||
    !materials.reviewer.installed.current() {
    return Err(AuthorizationDenied)
  }
  match
    host.check_signing_grant_original_locked(
      grant,
      self.original.request,
      scope.run_definition_cid,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    local_reviewer_proof_snapshot_locked(
      host.journal,
      self.original.request,
      scope.run_definition_cid,
      scope.checkpoint_cid,
    ) {
    Ok(actual) if actual == materials.original => ()
    Ok(_) => return Err(Checkpoint(StaleRevision))
    Err(issue) => return Err(issue)
  }
  // These are only the same original facts, not a new Local eligibility rule.
  // Common Checkpoint/Resolution admission retains its own cancellation,
  // settlement and Effect-unknown semantics independently of grant adoption.
  match issuer.require_current(host, self.original.operation_cid) {
    Ok(_) => ()
    Err(_) => return Err(AuthorizationDenied)
  }
  if !authority.current_for(host.journal, self.original.request) ||
    key.account.require_current_account() is Err(_) {
    return Err(AuthorizationDenied)
  }
  // Pure terminal original generation/lifetime fences follow every current
  // callback. Copied scope IDs alone cannot supply either original.
  match key.projection.export_original() {
    Ok(bytes) if bytes == key.exported => ()
    _ => return Err(CustodyLost)
  }
  match self.subject.original_subject_after_current() {
    Ok((invocation, unit)) if invocation == scope.run_invocation_cid &&
      unit == scope.unit_definition_cid => Ok(())
    _ => Err(CustodyLost)
  }
}

///|
// A different operation name must not replace an entered/unknown original for
// the same original signing subject. Explicit replacement is not a retry path.
// Two authenticated default originals additionally retain their first operation
// for that same Submission/Checkpoint/purpose: changing the decision/preimage,
// attempt or initialization cannot bypass its prior claimed/Unknown duty.
// Configured issuer-file operations keep their existing exact-key/preimage rule.
fn NativeLocalHostConnection::same_signing_operation_locked(
  self : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
  resolution_proof? : @checkpoint.PreparedResolutionProof? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard original.grant is SigningGrant(grant) else { return Err(ChangedIntent) }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let mut cursor = ""
  let mut observed = 0L
  while true {
    let row = match
      self.database.scan_after("client_local_grant_originals", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => return Ok(())
      Err(issue) => return Err(Physical(issue))
    }
    observed += 1L
    if observed > self.journal.max_records.to_int64() * 64L {
      return Err(CustodyLost)
    }
    let prior = match read_local_grant_original(self.epoch.crypto, row) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if prior.grant is SigningGrant(saved_grant) {
      let saved = @credential.local_signing_credential_grant_scope(saved_grant)
      if saved.submission_scope_cid == scope.submission_scope_cid &&
        saved.checkpoint_cid == scope.checkpoint_cid &&
        saved.purpose == scope.purpose &&
        prior.operation_id != original.operation_id &&
        (
          (original.initial_issue is Some(_) && prior.initial_issue is Some(_)) ||
          (
            saved.preimage == scope.preimage &&
            saved.key_configuration_cid == scope.key_configuration_cid &&
            saved.key_generation_cid == scope.key_generation_cid
          )
        ) {
        // Only the distinct, already-Succeeded original Approval may precede
        // its exact dependent Resolution. A renamed/changed Resolution,
        // unknown use or foreign key cannot use this continuation.
        guard original.initial_issue is Some(_) &&
          prior.initial_issue is Some(_) &&
          scope.purpose == @credential.ReviewerProof &&
          resolution_proof is Some(proof) &&
          proof.preimage() == scope.preimage &&
          proof.checkpoint().checkpoint_cid == scope.checkpoint_cid &&
          saved.key_id == scope.key_id &&
          saved.key_configuration_cid == scope.key_configuration_cid &&
          saved.key_generation_cid == scope.key_generation_cid &&
          saved.run_invocation_cid == scope.run_invocation_cid &&
          saved.unit_definition_cid == scope.unit_definition_cid &&
          saved.request_cid == scope.request_cid &&
          saved.principal == scope.principal &&
          saved.authority_scope_cid == scope.authority_scope_cid else {
          return Err(Checkpoint(NeedsOriginalContinuation))
        }
        let history = match
          local_initial_signing_original_history_locked(self, prior) {
          Ok(value) if value.observed_outcome() ==
            @credential_resource.Succeeded => value
          _ => return Err(Checkpoint(NeedsOriginalContinuation))
        }
        let (signature, evidence) = match
          local_initial_resolution_result_locked(
            self,
            prior,
            history.original_use(),
          ) {
          Ok((signature, Some(evidence))) => (signature, evidence)
          _ => return Err(Checkpoint(NeedsOriginalContinuation))
        }
        if proof.approval_proof_materials(
            evidence,
            @host.client_request_authority_scope_cid(original.request),
          ) !=
          Ok((saved.key_id, saved.preimage, signature)) {
          return Err(Checkpoint(NeedsOriginalContinuation))
        }
      }
    }
    cursor = row.key
  } nobreak {
    Err(CustodyLost)
  }
}

///|
/// Explicit adoption only, after original preparation. Separate current issuer
/// Account issue authorization is obtained for this exact immutable intent.
/// No start/approve/resume operation calls it implicitly, and no use is claimed.
pub fn NativeLocalReviewerSigningGrantOperation::adopt(
  self : NativeLocalReviewerSigningGrantOperation,
  issuer_principal : String,
  issuer_connection : String,
) -> Result[
  NativeLocalReviewerSigningGrantAcknowledgement,
  NativeLocalReviewerSigningGrantIssue,
] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let host = self.key.account.host
  let issuer = match
    host.acquire_credential_issuer(
      self.key.account.crypto,
      self.issuer_file.name,
      issuer_principal,
      issuer_connection,
      self.original.operation_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SigningGrantIssuer(issue))
  }
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let saved = host.journal.transaction(() => {
    match self.require_current_locked(issuer) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    issuer.append_owned_grant_original_locked(self.original, () => {
      self.require_current_locked(issuer)
    })
  })
  let after = self.require_current()
  let issuer_after = issuer.require_current(host, self.original.operation_cid)
  if saved is Err(TransactionUnknown) {
    return Err(SigningGrantJournal(TransactionUnknown))
  }
  match after {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match issuer_after {
    Ok(_) => ()
    Err(issue) => return Err(SigningGrantIssuer(issue))
  }
  // Neither issuer's clock nor the preceding purpose callbacks may leave
  // retired original references successful at the ACK boundary.
  match self.key.projection.export_original() {
    Ok(bytes) if bytes == self.key.exported => ()
    _ => return Err(SigningGrantUnavailable)
  }
  let scope = match self.original.grant {
    SigningGrant(value) =>
      @credential.local_signing_credential_grant_scope(value)
    _ => return Err(SigningGrantUnavailable)
  }
  match self.subject.original_subject_after_current() {
    Ok((invocation, unit)) if invocation == scope.run_invocation_cid &&
      unit == scope.unit_definition_cid => ()
    _ => return Err(SigningGrantUnavailable)
  }
  match saved {
    Ok(_) => Ok({ operation: self, })
    Err(issue) => Err(SigningGrantJournal(issue))
  }
}

///|
/// Original operation identity for reconciliation, not permission or an ACK.
pub fn NativeLocalReviewerSigningGrantOperation::operation_cid(
  self : NativeLocalReviewerSigningGrantOperation,
) -> String {
  self.original.operation_cid
}

///|
/// Read only the same original operation. Absence remains unresolved; this
/// never issues, adopts, claims, renews expiry or reconstructs missing custody.
/// History permission is original Client RunRead plus Reviewer/key current,
/// independently of issuer issue and grant-use expiry.
pub fn NativeLocalReviewerSigningGrantOperation::lookup_adoption(
  self : NativeLocalReviewerSigningGrantOperation,
) -> Result[
  NativeLocalReviewerSigningGrantAcknowledgement?,
  NativeLocalReviewerSigningGrantIssue,
] {
  let key = self.key
  let host = key.account.host
  let reviewer = self.materials.reviewer
  let authority = match
    native_local_policy_authority_for(
      host,
      key.account.crypto,
      reviewer.principal,
      reviewer.connection,
      self.original.request,
      ReadRunMaterials,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SigningGrantJournal(issue))
  }
  match key.require_signing_history_current(authority, self.original.request) {
    Ok(_) => ()
    Err(issue) => return Err(SigningGrantHistory(issue))
  }
  let read = host.journal.transaction(() => {
    if !authority.current_for(host.journal, self.original.request) ||
      key.account.require_current_account() is Err(_) {
      return Err(AuthorizationDenied)
    }
    host.lookup_local_grant_original_locked(key.account.crypto, self.original)
  })
  let after = key.require_signing_history_current(
    authority,
    self.original.request,
  )
  if read is Err(TransactionUnknown) {
    return Err(SigningGrantJournal(TransactionUnknown))
  }
  match after {
    Ok(_) => ()
    Err(issue) => return Err(SigningGrantHistory(issue))
  }
  match read {
    Ok(Some(_)) => Ok(Some({ operation: self, }))
    Ok(None) => Ok(None)
    Err(issue) => Err(SigningGrantJournal(issue))
  }
}

///|
/// Identity of the originally committed grant. Not a credential-use permit,
/// physical key correspondence, signature or Resolution acceptance.
pub fn NativeLocalReviewerSigningGrantAcknowledgement::grant_cid(
  self : NativeLocalReviewerSigningGrantAcknowledgement,
) -> String {
  local_original_grant_cid(self.operation.original.grant)
}
