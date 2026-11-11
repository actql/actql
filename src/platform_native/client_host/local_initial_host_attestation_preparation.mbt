///|
pub(all) enum NativeLocalInitialHostAttestationIssue {
  HostAttestationUnavailable
  HostAttestationOriginal(NativeLocalAdoptionIssue)
  HostAttestationAccount(NativeLocalSigningAccountIssue)
  HostAttestationReviewer(NativeLocalEffectReviewerBindingIssue)
  HostAttestationProof(NativeLocalInitialResolutionSigningIssue)
  HostAttestationBody(@checkpoint.ResolutionIssue)
  HostAttestationAuthorization(@authorization.DispatchBindingIssue)
  HostAttestationJournal(NativeClientRunJournalIssue)
  HostAttestationCredential(@credential_resource.NativeCredentialResourceIssue)
  HostAttestationPhysical(@crypto.NativeSignatureIssue)
}

///|
/// One durable unsigned preparation in the existing Host/Checkpoint assembly.
/// No use, physical signing attempt, signature or approval is issued here.
struct NativeLocalInitialHostAttestationPreparation {
  authenticated : NativeLocalAuthenticatedEffectReviewer
  account : NativeLocalInitialHostSigningAccount
  reviewer_current : NativeLocalInitialSigningCurrent
  original : NativeLocalGrantOriginal
  admitted : @checkpoint.AdmittedResolution
  wire : String
  scope : @credential.LocalSigningCredentialScope
}

///|
fn local_initial_host_attestation_current_locked(
  reviewer : NativeLocalInitialSigningCurrent,
  account : NativeLocalInitialHostSigningAccount,
) -> Result[Unit, NativeClientRunJournalIssue] {
  match reviewer.require_locked() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match account.require_current_account() {
    Err(_) => return Err(AuthorizationDenied)
    Ok(_) => ()
  }
  // Account callbacks cannot retire the retained paired subject and leave a
  // stale successful tuple. This terminal read invokes no callbacks.
  guard reviewer.subject.original_subject_after_current()
    is Ok((invocation, unit)) &&
    invocation == reviewer.scope.run_invocation_cid &&
    unit == reviewer.scope.unit_definition_cid else {
    return Err(AuthorizationDenied)
  }
  Ok(())
}

///|
/// Select the actual initialized Host Sign account explicitly. The complete
/// first unsigned wrapper and its trusted verification instant commit together
/// before any later signing use. Reopening reads that same instant/body; it
/// neither samples a replacement time nor repairs an absent preparation row.
pub fn NativeLocalAuthenticatedEffectReviewer::prepare_initial_host_attestation(
  self : NativeLocalAuthenticatedEffectReviewer,
  account : NativeLocalInitialHostSigningAccount,
  materials : NativeLocalReviewerProofMaterials,
  operation_id : String,
  approval_evidence_wire? : String? = None,
  earlier_valid_until? : Int64? = None,
) -> Result[
  NativeLocalInitialHostAttestationPreparation,
  NativeLocalInitialHostAttestationIssue,
] {
  let binding = self.binding
  let host = binding.host
  guard materials.proof is ResolutionOriginal(_) &&
    physical_equal(binding, materials.reviewer) &&
    physical_equal(host, account.original.reviewer.host) &&
    physical_equal(account.installed.host, host) &&
    account.installed.file == binding.installed.file &&
    account.installed.original_bytes == binding.installed.original_bytes &&
    self.registration == materials.registration &&
    self.authentication.proof_preimage == materials.proof.preimage() &&
    materials.key is InitialReviewerKey(reviewer_key) &&
    reviewer_key.original.exported == account.original.reviewer.exported &&
    reviewer_key.original.control_body == account.original.reviewer.control_body else {
    return Err(HostAttestationUnavailable)
  }
  match account.require_current_account() {
    Err(issue) => return Err(HostAttestationAccount(issue))
    Ok(_) => ()
  }
  if binding.read_current(self.registration.selection, self.registration.key_id) !=
    Some(self.registration) {
    return Err(HostAttestationUnavailable)
  }
  let reviewer_current = match
    materials.prepare_initial_signing_current(operation_id) {
    Ok(value) => value
    Err(issue) => return Err(HostAttestationProof(issue))
  }
  let reviewer_scope = reviewer_current.scope
  let key_configuration_cid = match
    local_adoption_digest(
      host.epoch.crypto,
      account.original.reviewer.control_body,
    ) {
    Ok(value) => value
    Err(_) => return Err(HostAttestationUnavailable)
  }
  let key_generation_cid = match
    local_adoption_digest(host.epoch.crypto, account.original.exported) {
    Ok(value) => value
    Err(_) => return Err(HostAttestationUnavailable)
  }
  let body_failure : Ref[@checkpoint.ResolutionIssue?] = Ref(None)
  let prepared = host.journal.transaction(() => {
    match
      local_initial_host_attestation_current_locked(reviewer_current, account) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    match host.local_grant_custody(host.epoch.crypto) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let row_key = match
      local_grant_original_key(host.epoch.crypto, binding.request, operation_id) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let retained = match
      host.database.read("client_local_grant_originals", row_key) {
      Err(@sqlite.NotFound) => None
      Err(issue) => return Err(Physical(issue))
      Ok(row) =>
        match
          read_local_grant_original(host.epoch.crypto, {
            key: row_key,
            body: row.body,
            revision: row.revision,
          }) {
          Ok(value) => Some(value)
          Err(issue) => return Err(issue)
        }
    }
    // The retained original is selected before the only clock sample. A
    // claimed/Unknown/failed operation cannot refresh its preparation/expiry.
    let sampled_at = match retained {
      None => @env.now().reinterpret_as_int64()
      Some(original) => {
        guard original.grant is SigningGrant(grant) &&
          original.initial_issue is Some(_) &&
          @credential.local_signing_credential_grant_scope(grant).purpose ==
          @credential.HostAttestation &&
          original.operation_id == operation_id &&
          @host.client_request_identity_relation(
            original.request,
            binding.request,
          )
          is @host.SameRequest else {
          return Err(ChangedIntent)
        }
        let fields = match
          read_local_initial_host_signing_control(
            host,
            account.original.reviewer.control_body,
          ) {
          Ok(value) => value
          Err(_) => return Err(CustodyLost)
        }
        let metadata = match
          read_local_initial_signing_issue_record(host, original, fields) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if metadata.connection != account.connection ||
          metadata.signing_resource != Some(account.resource) ||
          metadata.host_configuration_file != account.installed.file ||
          metadata.earlier_valid_until != earlier_valid_until {
          return Err(ChangedIntent)
        }
        metadata.sampled_at
      }
    }
    guard @values.epoch_milliseconds_timestamp(sampled_at) is Some(verified_at) else {
      return Err(Encoding)
    }
    let admitted = match
      @checkpoint.admit_checkpoint_resolution(
        materials.original.artifact,
        self.resolution_wire,
        approval_evidence_wire,
        self.authentication,
        [
          {
            key_id: self.registration.key_id,
            reviewer_id: self.registration.reviewer_id,
          },
        ],
        verified_at,
        self.limits,
      ) {
      Ok(value) => value
      Err(issue) => {
        body_failure.val = Some(issue)
        return Err(Encoding)
      }
    }
    match self.require_approval_signature_locked(admitted) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    match
      local_initial_host_attestation_current_locked(reviewer_current, account) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if materials.original.cancellation_requested &&
      admitted.decision == @checkpoint.Approved {
      return Err(Checkpoint(NeedsOriginalContinuation))
    }
    let wire = match admitted.prepared_wire(self.limits) {
      Ok(value) => value
      Err(issue) => {
        body_failure.val = Some(issue)
        return Err(Encoding)
      }
    }
    let scope = {
      ..reviewer_scope,
      authority_scope_cid: account.authority_scope_cid,
      principal: account.principal,
      key_configuration_cid,
      key_generation_cid,
      key_id: account.original.public_key.cid(),
      key_public_key_cid: account.original.public_key.cid(),
      preimage: admitted.attestation_preimage,
      purpose: @credential.HostAttestation,
    }
    match account.require_signing_scope(scope) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let original = match retained {
      Some(value) => {
        guard value.grant is SigningGrant(grant) &&
          @credential.local_signing_credential_grant_scope(grant) == scope else {
          return Err(ChangedIntent)
        }
        match local_initial_host_prepared_locked(host, value) {
          Ok(saved) if saved == @utf8.encode(wire) => value
          Ok(_) => return Err(ChangedIntent)
          Err(issue) => return Err(issue)
        }
      }
      None => {
        let value = match
          local_initial_host_signing_grant_original_locked(
            account,
            binding.request,
            scope,
            operation_id,
            sampled_at,
            earlier_valid_until,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        match
          append_local_owned_grant_original_locked(
            host,
            host.epoch.crypto,
            value,
            () => {
              local_initial_host_attestation_current_locked(
                reviewer_current, account,
              )
            },
            host_prepared=Some(wire),
          ) {
          Err(issue) => return Err(issue)
          Ok(_) => value
        }
      }
    }
    match
      local_initial_host_attestation_current_locked(reviewer_current, account) {
      Err(issue) => Err(issue)
      Ok(_) => Ok((original, admitted, wire, scope))
    }
  })
  let (original, admitted, wire, scope) = match prepared {
    Ok(value) => value
    Err(Encoding) if body_failure.val is Some(issue) =>
      return Err(HostAttestationBody(issue))
    Err(issue) => return Err(HostAttestationJournal(issue))
  }
  Ok({
    authenticated: self,
    account,
    reviewer_current,
    original,
    admitted,
    wire,
    scope,
  })
}
