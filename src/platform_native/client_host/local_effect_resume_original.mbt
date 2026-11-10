///|
// Original acknowledged Resolution material in the existing Local Host.
// This is not another signer, Run, grant, Resource or cleanup Owner. The
// existing Journal alone issues/fences the durable continuation lease.
struct NativeLocalEffectResumeOriginal {
  host : NativeLocalHostConnection
  crypto : @crypto.Library
  principal : String
  connection : String
  reference : NativeClientSubmissionReference
  request : @host.ClientRequestIdentity
  installed : NativeLocalInstalledEffectReviewer
  authentication : @checkpoint.HostAuthentication
  registration : @effect_resolution.NativeEffectReviewerRegistration
  record : NativeClientRunRecord
  invocation_cid : String
  unit_definition_cid : String
  mut subject : NativeLocalOriginalEffectSigningSubjectRead?
  mut host_key : NativeLocalInitialHostSigningOriginal?
  mut attempted : Bool
  mut prepared : Bool
  mut retired : Bool
  mut action : NativeClientEffectResumeAction?
  mut issue : NativeClientRunJournalIssue?
}

///|
/// Retain only the original successful Resolution commit and its actual
/// authorities. Never reopen the pre-answer signing scope after its revision
/// changes, re-sign, issue a key, or accept caller-supplied authority arrays.
pub fn NativeLocalInitialHostAttestationSigning::prepare_effect_resume_original(
  self : NativeLocalInitialHostAttestationSigning,
) -> Result[
  NativeLocalEffectResumeOriginal,
  NativeLocalInitialHostAttestationIssue,
] {
  if self.resume_original is Some(original) {
    if original.retired || !original.prepared {
      return Err(HostAttestationUnavailable)
    }
    return Ok(original)
  }
  guard self.entered &&
    !self.resume_entered &&
    !self.closed &&
    self.signature is Some(_) &&
    self.admitted_record is Some(record) &&
    record.checkpoint is Some(checkpoint) &&
    checkpoint.state.status == @publication.Resuming &&
    checkpoint.resolution_cid is Some(_) &&
    checkpoint.verified_wire is Some(_) &&
    checkpoint.resume_intent_id is Some(_) else {
    return Err(HostAttestationUnavailable)
  }
  self.resume_entered = true
  let preparation = self.preparation
  let binding = preparation.authenticated.binding
  let host = binding.host
  if !physical_equal(
      host.journal,
      preparation.account.original.reviewer.host.journal,
    ) ||
    record.request != binding.request ||
    @publication.publication_contract_identity(record.definition) !=
    preparation.scope.run_definition_cid ||
    checkpoint.artifact.checkpoint_cid != preparation.scope.checkpoint_cid {
    return Err(HostAttestationUnavailable)
  }
  // The current original already backed the preceding signer/commit. Add this
  // view, optional/result/authority array and callback/clock/claim controls
  // before constructing them. The already admitted record/verified wire are
  // borrowed originals here: this constructor emits/parses no wire and must
  // not reserve another copy sized by the Checkpoint admission ceiling.
  if binding.approval_scope is SavedApproval(owner) {
    match
      owner.capture.prepare_model_entry_construction(
        None,
        additional_controls=Some({
          record_headers: 20L,
          reference_slots: 48L,
          scalar_words: 32L,
          owned_utf16_units: 32L,
          owned_wire_bytes: 0L,
        }),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(HostAttestationOriginal(issue))
    }
  }
  let original : NativeLocalEffectResumeOriginal = {
    host,
    crypto: binding.crypto,
    principal: binding.principal,
    connection: binding.connection,
    reference: binding.reference,
    request: binding.request,
    installed: binding.installed,
    authentication: preparation.authenticated.authentication,
    registration: preparation.authenticated.registration,
    record,
    invocation_cid: preparation.scope.run_invocation_cid,
    unit_definition_cid: preparation.scope.unit_definition_cid,
    subject: Some(preparation.reviewer_current.subject),
    host_key: Some(preparation.account.original),
    attempted: false,
    prepared: false,
    retired: false,
    action: None,
    issue: None,
  }
  self.resume_original = Some(original)
  if !original.authority_current() {
    return Err(HostAttestationUnavailable)
  }
  original.prepared = true
  Ok(original)
}

///|
fn NativeLocalEffectResumeOriginal::authority_current(
  self : NativeLocalEffectResumeOriginal,
) -> Bool {
  guard !self.retired &&
    !self.host.closed &&
    !self.host.journal.fenced &&
    self.subject is Some(subject) &&
    subject.original_subject_after_current() is Ok((invocation, unit)) &&
    invocation == self.invocation_cid &&
    unit == self.unit_definition_cid &&
    self.host_key is Some(key) &&
    key.require_current() is Ok(_) &&
    self.installed.current() &&
    self.installed.reviewer.key_id == self.registration.key_id &&
    self.installed.reviewer.reviewer_id == self.registration.reviewer_id &&
    self.installed.reviewer.public_key_pem == self.registration.public_key_pem &&
    self.record.checkpoint is Some(checkpoint) else {
    return false
  }
  // Current Client Read, Reviewer registration and adopted Host key are
  // independent. Signing-use permission is not renewed for continuation.
  guard self.host.authority_scope_cid(
      self.principal,
      self.connection,
      self.crypto,
    )
    is Ok(authority) &&
    authority == @host.client_request_authority_scope_cid(self.request) &&
    self.host.authority_scope_cid(
      self.installed.reviewer.principal,
      self.installed.reviewer.connection,
      self.crypto,
    )
    is Ok(context) &&
    context == self.authentication.authority_context_cid else {
    return false
  }
  guard self.host.configuration() is Ok(configuration) &&
    configuration.configuration_cid() == self.authentication.policy_cid else {
    return false
  }
  let metadata = self.host.lookup_submitted_checkpoint_metadata(
    self.crypto,
    self.principal,
    self.connection,
    self.reference,
    self.request,
    @env.now().to_double(),
  )
  guard metadata is Ok(Some(actual)) &&
    actual.checkpoint_cid == checkpoint.artifact.checkpoint_cid &&
    actual.run_definition_cid ==
    @publication.publication_contract_identity(self.record.definition) &&
    !self.retired &&
    subject.original_subject_after_current() is Ok((invocation, unit)) &&
    invocation == self.invocation_cid &&
    unit == self.unit_definition_cid else {
    return false
  }
  // Mutable revisions belong to the Journal's claim/fence, not the old
  // Waiting signing scope. Never overwrite that scope to make it current.
  true
}

///|
/// One actual existing Journal claim. A second call, failure or Unknown never
/// reissues it. The original action remains DATA for the caller's observation;
/// every dispatch still requires the Journal's same-generation row fence.
pub fn NativeLocalEffectResumeOriginal::claim(
  self : NativeLocalEffectResumeOriginal,
  lease_ms : Int64,
) -> Result[
  NativeClientEffectResumeAction,
  NativeLocalInitialHostAttestationIssue,
] {
  if self.retired || !self.prepared || self.attempted {
    return Err(HostAttestationUnavailable)
  }
  self.attempted = true
  guard self.record.checkpoint is Some(checkpoint) &&
    self.host_key is Some(key) &&
    self.authority_current() else {
    return Err(HostAttestationUnavailable)
  }
  let result = self.host.journal.claim_effect_resume(
    self.request,
    self.crypto,
    self.authentication,
    [
      {
        key_id: self.registration.key_id,
        reviewer_id: self.registration.reviewer_id,
      },
    ],
    [{ key_id: key.public_key.cid(), public_key_pem: key.public_key_pem, }],
    key.public_key.cid(),
    lease_ms,
    checkpoint.binding,
    () => self.authority_current(),
    () => {
      let now = @env.now().reinterpret_as_int64()
      (@values.epoch_milliseconds_timestamp(now).unwrap_or(""), now)
    },
  )
  match result {
    Ok(action) => {
      self.action = Some(action)
      Ok(action)
    }
    Err(issue) => {
      self.issue = Some(issue)
      Err(HostAttestationJournal(issue))
    }
  }
}

///|
/// Observe this same issued claim, never recreate one or upgrade settlement.
pub fn NativeLocalEffectResumeOriginal::fence(
  self : NativeLocalEffectResumeOriginal,
) -> Result[
  NativeClientEffectResumeFence,
  NativeLocalInitialHostAttestationIssue,
] {
  if self.retired {
    return Err(HostAttestationUnavailable)
  }
  let claim = match self.action {
    Some(Claimed(value)) | Some(SettlementOnly(value)) => value
    _ => return Err(HostAttestationUnavailable)
  }
  self.host.journal
  .effect_resume_fence(claim, () => self.authority_current(), () => {
    @env.now().reinterpret_as_int64()
  })
  .map_err(issue => HostAttestationJournal(issue))
}

///|
/// Record custody for this approved original row through the existing Journal.
/// A successful dispatch is not target authorization, a physical send, response
/// evidence or a cleanup ACK. The installed write caller must retain its exact
/// request and check its current target/authorization before entering physical IO.
/// Settlement-only, foreign Preview/Unit/row and retired originals cannot send.
pub fn NativeLocalEffectResumeOriginal::dispatch_row(
  self : NativeLocalEffectResumeOriginal,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  basis : @effect.EffectLedgerBasis,
) -> Result[
  NativeClientEffectRowDispatchAction,
  NativeLocalInitialHostAttestationIssue,
] {
  guard !self.retired &&
    self.prepared &&
    self.action is Some(Claimed(claim)) &&
    self.record.checkpoint is Some(checkpoint) &&
    basis.unit_definition_cid == self.unit_definition_cid &&
    basis.effect_preview_cid ==
    checkpoint.artifact.checkpoint.required_artifact_cid &&
    @publication.effect_preview_semantic_identity(preview) ==
    basis.effect_preview_cid &&
    @publication.effect_preview_run_identity(preview) ==
    @publication.publication_contract_identity(self.record.definition) &&
    @publication.effect_preview_member_kind(preview, member_index) is Some(kind) &&
    @publication.effect_preview_ordered_row_identity(
      preview, member_index, row_index,
    )
    is Some(row) else {
    return Err(HostAttestationUnavailable)
  }
  // Preserve the already admitted Preview; do not re-author or recompile it.
  // Common's original single-row binding checks scope, locator, key and order.
  if @effect.admit_effect_single_row(
      preview,
      member_index,
      row_index,
      kind,
      @host.client_request_logical_scope(self.request),
      row,
      locator,
      key,
    )
    is Err(_) {
    return Err(HostAttestationUnavailable)
  }
  // Journal rechecks the actual lease generation and current original around
  // its clock observation and commits prepared+dispatching with the Run witness.
  self.host.journal
  .record_effect_row_dispatch(
    claim,
    locator,
    key,
    basis,
    () => self.authority_current(),
    () => @env.now().reinterpret_as_int64(),
  )
  .map_err(issue => HostAttestationJournal(issue))
}

///|
/// Alias retirement only. Durable intent/generation and consumed work remain.
pub fn NativeLocalEffectResumeOriginal::retire_read_aliases(
  self : NativeLocalEffectResumeOriginal,
) -> Unit {
  self.retired = true
  self.subject = None
  self.host_key = None
  self.action = None
}
