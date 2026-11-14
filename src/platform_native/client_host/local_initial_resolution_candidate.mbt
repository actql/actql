///|
// A bounded read view of the same immutable Journal records, not a signing or
// approval capability. The caller retains the original current Reviewer scope.
priv struct NativeLocalRetainedResolutionCandidate {
  wire : String
  scope : @credential.LocalSigningCredentialScope
}

///|
// Re-admit the retained body's actual fields with the existing Core codec.
// Removing its two signed transport fields preserves the original decision
// time; it neither authors a replacement body nor selects a fresh timestamp.
fn local_initial_resolution_candidate_proof(
  checkpoint : @checkpoint.SealedCheckpoint,
  wire : String,
  scope : @credential.LocalSigningCredentialScope,
  signature : String,
  cancellation_requested : Bool,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let limits = native_checkpoint_limits()
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let unsigned = try {
    let value = @canonical.from_source(
      source,
      limits.max_nodes,
      limits.max_depth,
      limits.max_wire_bytes,
      data_keys=true,
    )
    guard @canonical.object_without_field(value, "proof") is Some(without_proof) &&
      @canonical.object_without_field(without_proof, "resolution_cid")
      is Some(body) else {
      return Err(CustodyLost)
    }
    @canonical.stringify_value(
      body,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
  } catch {
    _ => return Err(CustodyLost)
  }
  let proof = match
    @checkpoint.prepare_resolution_proof(checkpoint, unsigned, limits) {
    Ok(value) if value.preimage() == scope.preimage &&
      checkpoint.checkpoint_cid == scope.checkpoint_cid &&
      checkpoint.checkpoint.checkpoint_id == scope.checkpoint_id => value
    _ => return Err(CustodyLost)
  }
  if cancellation_requested && proof.decision() == @checkpoint.Approved {
    return Err(Checkpoint(NeedsOriginalContinuation))
  }
  if @checkpoint.seal_prepared_resolution_proof(proof, scope.key_id, signature) !=
    Ok(wire) {
    return Err(CustodyLost)
  }
  Ok(())
}

///|
fn NativeLocalEffectReviewerBinding::read_initial_resolution_candidate_locked(
  self : NativeLocalEffectReviewerBinding,
  key : NativeLocalInitialReviewerSigningKey,
  operation_id : String,
) -> Result[NativeLocalRetainedResolutionCandidate, NativeClientRunJournalIssue] {
  let host = self.host
  if !host.journal.transaction_active || host.journal.fenced {
    return Err(Fenced)
  }
  match
    host.local_grant_custody(
      self.crypto,
      capture=key.original.original_read.map(value => value.0),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let row_key = match
    local_grant_original_key(self.crypto, self.request, operation_id) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let row = match host.database.read("client_local_grant_originals", row_key) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let original = match
    read_local_grant_original(self.crypto, {
      key: row_key,
      body: row.body,
      revision: row.revision,
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard original.grant is SigningGrant(grant) &&
    original.initial_issue is Some(_) &&
    original.operation_id == operation_id &&
    @host.client_request_identity_relation(original.request, self.request) ==
    @host.SameRequest else {
    return Err(ChangedIntent)
  }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  if scope.checkpoint_cid != self.original.checkpoint_cid ||
    scope.run_definition_cid != self.original.run_definition_cid ||
    InitialReviewerKey(key).require_signing_key_scope(scope) is Err(_) {
    return Err(ChangedIntent)
  }
  let history = match
    @credential_resource.prepare_native_local_original_signing_history_candidate(
      host.database,
      grant,
    ) {
    Ok(value) if value.observed_outcome() == @credential_resource.Succeeded =>
      value
    _ => return Err(CustodyLost)
  }
  // Returning a candidate keeps the signing path's actual expiry/revocation
  // checks; a historical Succeeded tag alone never provides current use.
  match
    @credential_resource.check_native_local_original_signing_use_in_transaction(
      host.database,
      grant,
      history.original_use(),
      scope,
      @env.now().reinterpret_as_int64(),
    ) {
    Ok(_) => ()
    Err(_) => return Err(AuthorizationDenied)
  }
  let (signature, wire) = match
    local_initial_resolution_result_locked(
      host,
      original,
      history.original_use(),
    ) {
    Ok((signature, Some(value))) => (signature, value)
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  let snapshot = match
    local_reviewer_proof_snapshot_locked(
      host.journal,
      self.request,
      self.original.run_definition_cid,
      self.original.checkpoint_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if snapshot.revision != self.original.revision ||
    snapshot.state != self.original.state ||
    snapshot.cancellation_requested != self.original.cancellation_requested {
    return Err(Checkpoint(StaleRevision))
  }
  match
    local_initial_resolution_candidate_proof(
      snapshot.artifact,
      wire,
      scope,
      signature,
      snapshot.cancellation_requested,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok({ wire, scope, })
}

///|
/// Restore only the complete original signed candidate, without constructing
/// another unsigned body, sampling a decision time, claiming or signing again.
/// Current Client/Reviewer, original paired subject, live original Credential
/// and physical signature verification still precede return. Host attestation,
/// full Checkpoint admission, durable resolution commit and resume are separate.
pub fn NativeLocalEffectReviewerBinding::restore_initial_resolution_candidate(
  self : NativeLocalEffectReviewerBinding,
  operation_id : String,
) -> Result[
  NativeLocalAuthenticatedEffectReviewer,
  NativeLocalEffectReviewerBindingIssue,
] {
  guard self.installed.initial_original is Some(original) else {
    return Err(ReviewerUnavailable)
  }
  let key = match
    self.host.acquire_initial_reviewer_signing_key(original, self.installed) {
    Ok(value) => value
    Err(_) => return Err(ReviewerUnavailable)
  }
  let registration = match key.read_current_reviewer(self) {
    Ok(value) => value
    Err(_) => return Err(ReviewerUnavailable)
  }
  let subject = match
    self.approval_scope.read_original_signing_subject_for(
      self.request,
      self.original.run_definition_cid,
      self.original.checkpoint_cid,
    ) {
    Ok(value) => value
    Err(_) => return Err(ReviewerUnavailable)
  }
  let candidate = match
    self.host.journal.transaction(() => {
      self.read_initial_resolution_candidate_locked(key, operation_id)
    }) {
    Ok(value) => value
    Err(issue) => return Err(ReviewerJournal(issue))
  }
  guard subject.original_subject_after_current() is Ok((invocation, unit)) &&
    invocation == candidate.scope.run_invocation_cid &&
    unit == candidate.scope.unit_definition_cid else {
    return Err(ReviewerUnavailable)
  }
  let authenticated = match
    self.authenticate_resolution(candidate.wire, native_checkpoint_limits()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if authenticated.authentication.proof_preimage != candidate.scope.preimage ||
    authenticated.registration != registration ||
    !(key.read_current_reviewer(self) is Ok(actual) && actual == registration) {
    return Err(ReviewerUnavailable)
  }
  // Last caller/current callbacks precede a fresh actual Credential snapshot.
  // A changed/revoked use or missing wire after verification cannot be hidden.
  match
    self.host.journal.transaction(() => {
      let after = match
        self.read_initial_resolution_candidate_locked(key, operation_id) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if after.wire != candidate.wire || after.scope != candidate.scope {
        return Err(ChangedIntent)
      }
      Ok(())
    }) {
    Ok(_) => ()
    Err(issue) => return Err(ReviewerJournal(issue))
  }
  guard subject.original_subject_after_current() is Ok((invocation, unit)) &&
    invocation == candidate.scope.run_invocation_cid &&
    unit == candidate.scope.unit_definition_cid &&
    key.finish_original_projection() is Ok(_) else {
    return Err(ReviewerUnavailable)
  }
  Ok(authenticated)
}
