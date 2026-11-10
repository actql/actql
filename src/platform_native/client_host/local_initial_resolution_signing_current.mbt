///|
// A private read view in the existing Host operation, not a current ticket or
// permission cache. Complete callbacks run outside the Journal TX; the closed
// predicate below rereads actual Account/key/row originals inside that TX.
priv struct NativeLocalInitialSigningCurrent {
  materials : NativeLocalReviewerProofMaterials
  key : NativeLocalInitialReviewerSigningKey
  scope : @credential.LocalSigningCredentialScope
  authority : NativeLocalPolicyAuthority
  subject : NativeLocalOriginalEffectSigningSubjectRead
  original_use : (
    NativeLocalGrantOriginal,
    @credential.LocalSigningCredentialUse,
  )?
}

///|
fn NativeLocalReviewerProofMaterials::initial_signing_current(
  self : NativeLocalReviewerProofMaterials,
  scope : @credential.LocalSigningCredentialScope,
  original_use? : (
    NativeLocalGrantOriginal,
    @credential.LocalSigningCredentialUse,
  )? = None,
) -> Result[
  NativeLocalInitialSigningCurrent,
  NativeLocalInitialResolutionSigningIssue,
] {
  let subject = match self.read_original_signing_scope(scope) {
    Err(issue) => return Err(OriginalSigningProof(issue))
    Ok(value) => value
  }

  if self.original.cancellation_requested &&
    self.proof.decision() == @checkpoint.Approved {
    return Err(OriginalSigningJournal(Checkpoint(NeedsOriginalContinuation)))
  }
  guard self.key is InitialReviewerKey(key) else {
    return Err(OriginalSigningUnavailable)
  }
  let reviewer = self.reviewer
  let authority = match
    native_local_policy_authority_for(
      reviewer.host,
      reviewer.crypto,
      reviewer.principal,
      reviewer.connection,
      reviewer.request,
      ReadRunMaterials,
    ) {
    Err(issue) => return Err(OriginalSigningJournal(issue))
    Ok(value) => value
  }
  // Authority selection may call current after the scope read. Recheck the
  // same material and retain its original subject's terminal lifetime fence;
  // do not discard the read and repeat the whole scope/Submission traversal.
  match self.require_current() {
    Err(issue) => return Err(OriginalSigningProof(issue))
    Ok(_) => ()
  }
  guard subject.original_subject_after_current() is Ok((invocation, unit)) &&
    invocation == scope.run_invocation_cid &&
    unit == scope.unit_definition_cid else {
    return Err(OriginalSigningUnavailable)
  }
  Ok({ materials: self, key, scope, authority, subject, original_use, })
}

///|
// No nested Journal transaction or caller-supplied Allow is accepted.
// The same immutable subject is checked after every actual current/key/row
// observation. No Store acquisition or renewed capture holding occurs here.
fn NativeLocalInitialSigningCurrent::require_locked(
  self : NativeLocalInitialSigningCurrent,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let materials = self.materials
  let reviewer = materials.reviewer
  let host = reviewer.host
  if !host.journal.transaction_active ||
    host.journal.fenced ||
    !physical_equal(host, self.key.original.host) ||
    !self.authority.current_for(host.journal, reviewer.request) ||
    !self.key.installed.current() ||
    self.key.require_current() is Err(_) {
    return Err(AuthorizationDenied)
  }
  let actual = match
    local_reviewer_proof_snapshot_locked(
      host.journal,
      reviewer.request,
      reviewer.original.run_definition_cid,
      materials.original.artifact.checkpoint_cid,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if actual != materials.original {
    return Err(Checkpoint(StaleRevision))
  }
  if actual.cancellation_requested &&
    materials.proof.decision() == @checkpoint.Approved {
    return Err(Checkpoint(NeedsOriginalContinuation))
  }
  // Each role is fresh: original Client RunRead and independent Reviewer
  // resolve are not interchangeable. The configured registration is immutable
  // only while its actual original selection/key/account remains current.
  let installed = self.key.installed
  let registration = materials.registration
  if installed.reviewer.reviewer_id != registration.reviewer_id ||
    installed.reviewer.key_id != registration.key_id ||
    installed.reviewer.public_key_pem != registration.public_key_pem ||
    self.key.fields.authority_scope_cid != registration.authority_context_cid ||
    self.key.fields.account_configuration_cid != registration.policy_cid ||
    !self.authority.current_for(host.journal, reviewer.request) ||
    !installed.current() ||
    self.key.finish_original_projection() is Err(_) {
    return Err(AuthorizationDenied)
  }
  if self.original_use is Some((original, credential_use)) {
    guard original.grant is SigningGrant(grant) else { return Err(CustodyLost) }
    match
      @credential_resource.check_native_local_original_signing_use_in_transaction(
        host.database,
        grant,
        credential_use,
        self.scope,
        @env.now().reinterpret_as_int64(),
      ) {
      Err(@credential_resource.Journal(issue)) => return Err(Physical(issue))
      Err(_) => return Err(AuthorizationDenied)
      Ok(_) => ()
    }
  }
  // This last original-lifetime observation invokes no callbacks and cannot
  // renew a retired capture even when all immutable CIDs still match.
  guard self.subject.original_subject_after_current() is Ok((invocation, unit)) &&
    invocation == self.scope.run_invocation_cid &&
    unit == self.scope.unit_definition_cid else {
    return Err(AuthorizationDenied)
  }
  Ok(())
}
