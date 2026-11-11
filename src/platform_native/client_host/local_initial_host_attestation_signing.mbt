///|
/// Retained physical child of the same Local Host. The already committed
/// preparation cannot be changed by this operation or a later history read.
struct NativeLocalInitialHostAttestationSigning {
  preparation : NativeLocalInitialHostAttestationPreparation
  physical : @crypto.OriginalKeySigningAttempt
  mut entered : Bool
  mut closed : Bool
  mut original_use : @credential.LocalSigningCredentialUse?
  mut signature : String?
  mut admitted_record : NativeClientRunRecord?
  mut resume_original : NativeLocalEffectResumeOriginal?
  mut resume_entered : Bool
}

///|
fn NativeLocalInitialHostAttestationPreparation::require_current_locked(
  self : NativeLocalInitialHostAttestationPreparation,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let binding = self.authenticated.binding
  let host = binding.host
  match
    local_initial_host_attestation_current_locked(
      self.reviewer_current,
      self.account,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The helper just observed this account and then the same subject through
  // a noncallback fence. Compare its immutable scope without invoking all
  // Account/key/current callbacks a second time at this one boundary.
  match self.account.require_signing_scope_after_current(self.scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let key = match
    local_grant_original_key(
      host.epoch.crypto,
      binding.request,
      self.original.operation_id,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let packet = match local_grant_original_packet(self.original) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard host.database.read("client_local_grant_originals", key) is Ok(row) &&
    row.revision == 0L &&
    row.body == packet else {
    return Err(CustodyLost)
  }
  match
    host.check_initial_host_attestation_grant_original_locked(
      self.original,
      self.scope.run_definition_cid,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match local_initial_host_prepared_locked(host, self.original) {
    Ok(value) if value == @utf8.encode(self.wire) => ()
    Ok(_) => return Err(ChangedIntent)
    Err(issue) => return Err(issue)
  }
  guard self.reviewer_current.subject.original_subject_after_current()
    is Ok((invocation, unit)) &&
    invocation == self.scope.run_invocation_cid &&
    unit == self.scope.unit_definition_cid else {
    return Err(AuthorizationDenied)
  }
  Ok(())
}

///|
fn NativeLocalInitialHostAttestationPreparation::require_current(
  self : NativeLocalInitialHostAttestationPreparation,
) -> Result[Unit, NativeLocalInitialHostAttestationIssue] {
  let authenticated = self.authenticated
  let binding = authenticated.binding
  match self.reviewer_current.materials.require_current() {
    Err(issue) => return Err(HostAttestationProof(OriginalSigningProof(issue)))
    Ok(_) => ()
  }
  if self.reviewer_current.key.original.original_read is Some(_) &&
    self.reviewer_current.materials.reviewer.approval_scope is SavedApproval(_) {
    // require_current just completed this SAME material's registration read
    // and terminal key/current checks. Only these identity/data comparisons
    // intervene; do not add another whole caller/clock traversal. Independent
    // Host Sign and the actual transaction/physical gates remain below.
    if !physical_equal(self.reviewer_current.materials.reviewer, binding) ||
      self.reviewer_current.materials.registration !=
      authenticated.registration {
      return Err(HostAttestationUnavailable)
    }
  } else {
    if binding.read_current(
        authenticated.registration.selection,
        authenticated.registration.key_id,
      ) !=
      Some(authenticated.registration) {
      return Err(HostAttestationUnavailable)
    }
  }
  binding.host.journal
  .transaction(() => self.require_current_locked())
  .map_err(issue => HostAttestationJournal(issue))
}

///|
/// Prepare the original Library child after full preparation COMMIT returns.
/// No secret is read and no use is claimed until sign_once. The parent retains
/// this same child before any following fallible callback/operation.
pub fn NativeLocalInitialHostAttestationPreparation::prepare_signing(
  self : NativeLocalInitialHostAttestationPreparation,
) -> Result[
  NativeLocalInitialHostAttestationSigning,
  NativeLocalInitialHostAttestationIssue,
] {
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let host = self.authenticated.binding.host
  if host.host_attestation_signing_attempt is Some(previous) && !previous.closed {
    return Err(HostAttestationUnavailable)
  }
  let key = self.account.original
  let public_key = match key.public_key.raw32() {
    Ok(value) => value
    Err(_) => return Err(HostAttestationUnavailable)
  }
  let physical = match
    host.epoch.crypto.prepare_original_key_signing_attempt(
      key.projection,
      public_key,
      @utf8.encode(self.scope.preimage),
    ) {
    Ok(value) => value
    Err(issue) => return Err(HostAttestationPhysical(issue))
  }
  let signing : NativeLocalInitialHostAttestationSigning = {
    preparation: self,
    physical,
    entered: false,
    closed: false,
    original_use: None,
    signature: None,
    admitted_record: None,
    resume_original: None,
    resume_entered: false,
  }
  host.host_attestation_signing_attempt = Some(signing)
  self.require_current().map(_ => signing)
}

///|
fn NativeLocalInitialHostAttestationSigning::require_current(
  self : NativeLocalInitialHostAttestationSigning,
) -> Result[Unit, NativeLocalInitialHostAttestationIssue] {
  match self.physical.require_original_owner() {
    Err(issue) => return Err(HostAttestationPhysical(issue))
    Ok(_) => ()
  }
  let host = self.preparation.authenticated.binding.host
  guard !self.closed &&
    !host.closed &&
    host.host_attestation_signing_attempt is Some(actual) &&
    physical_equal(actual, self) else {
    return Err(HostAttestationUnavailable)
  }
  self.preparation.require_current()
}

///|
fn NativeLocalInitialHostAttestationSigning::require_use_locked(
  self : NativeLocalInitialHostAttestationSigning,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let preparation = self.preparation
  match preparation.require_current_locked() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let host = preparation.authenticated.binding.host
  guard self.original_use is Some(signing_use) &&
    preparation.original.grant is SigningGrant(grant) else {
    return Err(CustodyLost)
  }
  match
    @credential_resource.check_native_local_initial_host_signing_use_in_transaction(
      host.database,
      grant,
      signing_use,
      preparation.scope,
      @env.now().reinterpret_as_int64(),
    ) {
    Err(@credential_resource.Journal(issue)) => return Err(Physical(issue))
    Err(_) => return Err(AuthorizationDenied)
    Ok(_) => ()
  }
  guard preparation.reviewer_current.subject.original_subject_after_current()
    is Ok((invocation, unit)) &&
    invocation == preparation.scope.run_invocation_cid &&
    unit == preparation.scope.unit_definition_cid else {
    return Err(AuthorizationDenied)
  }
  Ok(())
}

///|
/// Claim the fixed original use in a separate confirmed TX after preparation.
/// Uncertain or entered history cannot re-enter the actual physical signer.
pub fn NativeLocalInitialHostAttestationSigning::sign_once(
  self : NativeLocalInitialHostAttestationSigning,
) -> Result[String, NativeLocalInitialHostAttestationIssue] {
  match self.physical.require_original_owner() {
    Err(issue) => return Err(HostAttestationPhysical(issue))
    Ok(_) => ()
  }
  native_timing_begin(34)
  defer native_timing_end(34)
  if self.entered || self.closed {
    return Err(HostAttestationUnavailable)
  }
  self.entered = true
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let preparation = self.preparation
  let host = preparation.authenticated.binding.host
  guard preparation.original.grant is SigningGrant(grant) else {
    return Err(HostAttestationUnavailable)
  }
  let retained_signature : Ref[String?] = Ref(None)
  let credential_failure : Ref[
    @credential_resource.NativeCredentialResourceIssue?,
  ] = Ref(None)
  let claimed = host.journal.transaction(() => {
    match preparation.require_current_locked() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let history = @credential_resource.prepare_native_local_initial_host_signing_history_candidate(
      host.database,
      grant,
    )
    let signing_use = match history {
      Ok(value) if value.observed_outcome() == @credential_resource.Succeeded => {
        let signing_use = value.original_use()
        match
          local_initial_resolution_result_locked(
            host,
            preparation.original,
            signing_use,
          ) {
          Ok((signature, Some(_))) => retained_signature.val = Some(signature)
          Ok(_) => return Err(CustodyLost)
          Err(issue) => return Err(issue)
        }
        signing_use
      }
      Ok(_) => return Err(CustodyLost)
      Err(@credential_resource.Journal(@sqlite.NotFound)) =>
        // This role-specific claim reader independently refuses any existing
        // ordinal, missing use, orphan outcome or other earlier attempt.
        match
          @credential_resource.claim_native_local_initial_host_signing_use_in_transaction(
            host.database,
            grant,
            preparation.scope,
            @env.now().reinterpret_as_int64(),
          ) {
          Ok(value) => value
          Err(issue) => {
            credential_failure.val = Some(issue)
            return Err(CustodyLost)
          }
        }
      Err(issue) => {
        credential_failure.val = Some(issue)
        return Err(CustodyLost)
      }
    }
    self.original_use = Some(signing_use)
    self.require_use_locked()
  })
  match claimed {
    Err(CustodyLost) if credential_failure.val is Some(issue) =>
      return Err(HostAttestationCredential(issue))
    Err(issue) => return Err(HostAttestationJournal(issue))
    Ok(_) => ()
  }
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if retained_signature.val is None {
    match preparation.account.original.reviewer.check_callback_current() {
      Err(issue) => return Err(HostAttestationOriginal(issue))
      Ok(_) => ()
    }
  }
  match host.journal.transaction(() => self.require_use_locked()) {
    Err(issue) => return Err(HostAttestationJournal(issue))
    Ok(_) => ()
  }
  let signature = match retained_signature.val {
    Some(value) => value
    None => {
      let transport = match self.physical.sign_once() {
        Ok(value) => value
        Err(issue) => return Err(HostAttestationPhysical(issue))
      }
      match preparation.account.original.reviewer.check_callback_current() {
        Err(issue) => return Err(HostAttestationOriginal(issue))
        Ok(_) => ()
      }
      let signature = match
        local_initial_resolution_signature_standard(transport) {
        Ok(value) => value
        Err(_) => return Err(HostAttestationUnavailable)
      }
      match self.require_current() {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard self.original_use is Some(signing_use) else {
        return Err(HostAttestationUnavailable)
      }
      match
        host.journal.transaction(() => {
          match self.require_use_locked() {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          match
            store_local_initial_resolution_signature_locked(
              host,
              preparation.original,
              signing_use,
              signature,
              attested=Some(preparation.admitted),
              attested_limits=preparation.authenticated.limits,
            ) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          self.require_use_locked()
        }) {
        Err(issue) => return Err(HostAttestationJournal(issue))
        Ok(_) => signature
      }
    }
  }
  self.signature = Some(signature)
  self.original_verified_resolution()
}

///|
/// Return only this same complete stored wrapper, through fresh current and
/// live-use checks. A succeeded tag alone supplies no wire or admission.
pub fn NativeLocalInitialHostAttestationSigning::original_verified_resolution(
  self : NativeLocalInitialHostAttestationSigning,
) -> Result[String, NativeLocalInitialHostAttestationIssue] {
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.original_use is Some(signing_use) &&
    self.signature is Some(signature) else {
    return Err(HostAttestationUnavailable)
  }
  let preparation = self.preparation
  let host = preparation.authenticated.binding.host
  let retained = host.journal.transaction(() => {
    match self.require_use_locked() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let history = match
      local_initial_signing_original_history_locked(host, preparation.original) {
      Ok(value) if value.observed_outcome() == @credential_resource.Succeeded =>
        value
      _ => return Err(CustodyLost)
    }
    if @credential.local_signing_credential_use_cid(history.original_use()) !=
      @credential.local_signing_credential_use_cid(signing_use) {
      return Err(CustodyLost)
    }
    match
      local_initial_resolution_result_locked(
        host,
        preparation.original,
        signing_use,
      ) {
      Ok((actual, Some(wire))) if actual == signature => Ok(wire)
      Ok(_) => Err(CustodyLost)
      Err(issue) => Err(issue)
    }
  })
  let wire = match retained {
    Ok(value) => value
    Err(issue) => return Err(HostAttestationJournal(issue))
  }
  match
    @checkpoint.seal_verified_resolution(
      preparation.admitted,
      preparation.scope.key_id,
      signature,
      preparation.authenticated.limits,
    ) {
    Ok(value) if value.wire == wire => ()
    _ => return Err(HostAttestationUnavailable)
  }
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  host.journal
  .transaction(() => self.require_use_locked())
  .map(_ => wire)
  .map_err(issue => HostAttestationJournal(issue))
}

///|
pub fn NativeLocalInitialHostAttestationSigning::close_checked(
  self : NativeLocalInitialHostAttestationSigning,
) -> Result[Unit, @crypto.NativeSignatureIssue] {
  self.physical
  .close_checked()
  .map(_ => {
    self.closed = true
    self.signature = None
  })
}

///|
/// Apply this same physical initial-Host wrapper through the existing full
/// Native verifier and Resolution transaction. No caller authority/key array,
/// replacement timestamp, resume claim or Effect send is accepted here.
pub fn NativeLocalInitialHostAttestationSigning::admit_original_resolution(
  self : NativeLocalInitialHostAttestationSigning,
) -> Result[NativeClientRunRecord, NativeLocalInitialHostAttestationIssue] {
  native_timing_begin(35)
  defer native_timing_end(35)
  let wire = match self.original_verified_resolution() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let preparation = self.preparation
  let authenticated = preparation.authenticated
  let binding = authenticated.binding
  let host = binding.host
  let original = preparation.account.original
  let current = () => {
    self.require_current() is Ok(_) &&
    host.journal.transaction(() => self.require_use_locked()) is Ok(_)
  }
  if !current() {
    return Err(HostAttestationUnavailable)
  }
  let authentication = match
    @effect_resolution.authenticate_native_effect_wrapper_reviewer(
      {
        crypto: binding.crypto,
        current_site: current,
        read_current: (selection, key) => binding.read_current(selection, key),
      },
      authenticated.registration.selection,
      wire,
      authenticated.resolution_wire,
      authenticated.limits,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(HostAttestationReviewer(ReviewerAuthentication(issue)))
  }
  if authentication != authenticated.authentication || !current() {
    return Err(HostAttestationUnavailable)
  }
  // require_current has rechecked the original paired keys and explicit Sign
  // Account. Verification consumes only this actual original Host public key.
  // The existing commit owner samples after physical verification. A saved
  // verification instant cannot extend the actual open-Checkpoint deadline.
  let now = () => {
    @values.epoch_milliseconds_timestamp(@env.now().reinterpret_as_int64()).unwrap_or(
      "",
    )
  }
  host.journal
  .resolve_effect_checkpoint(
    binding.request,
    binding.crypto,
    wire,
    authentication,
    [
      {
        key_id: authenticated.registration.key_id,
        reviewer_id: authenticated.registration.reviewer_id,
      },
    ],
    [
      {
        key_id: original.public_key.cid(),
        public_key_pem: original.public_key_pem,
      },
    ],
    current,
    now,
  )
  .map(record => {
    // Retain the actual acknowledged commit before another callback or the
    // caller's physical signer close. No incoming record can issue this view.
    self.admitted_record = Some(record)
    record
  })
  .map_err(issue => HostAttestationJournal(issue))
}
