///|
/// One Model Checkpoint associated with its original admitted Run and review.
/// Its scope carries linked originals, not the execution owner's opaque
/// complete-input/call-set guarantee or a current physical dispatch permit.
pub struct ModelCheckpointBinding {
  priv checkpoint : SealedCheckpoint
  priv scope : @publication.BoundModelInvocationScope
  priv review_expires_at : String
}

///|
pub fn bind_model_checkpoint(
  checkpoint : SealedCheckpoint,
  scope : @publication.BoundModelInvocationScope,
  review : @publication.RunEvidenceValue,
) -> Result[ModelCheckpointBinding, ResolutionIssue] {
  let request = checkpoint.checkpoint
  let (run_id, definition_cid, unit_id) = @publication.model_invocation_scope_run(
    scope,
  )
  if request.kind != ModelInvocation ||
    request.phase != Preflight ||
    request.subject !=
    RunUnit(run_id~, unit_id~, run_definition_cid=definition_cid) ||
    request.required_artifact_cid !=
    @publication.model_invocation_scope_cid(scope) {
    return Err(CheckpointBindingMismatch("model_invocation_scope"))
  }
  if request.review_projection_cid !=
    @publication.run_evidence_value_identity(review) ||
    @publication.check_model_invocation_review(scope, review) is Err(_) {
    return Err(EvidenceMismatch("model_review_projection"))
  }
  guard @publication.model_invocation_review_expires_at(review)
    is Some(review_expires_at) else {
    return Err(EvidenceMismatch("model_review_projection.expires_at"))
  }
  if review_expires_at <= request.created_at {
    return Err(EvidenceMismatch("model_review_projection.expires_at"))
  }
  Ok({ checkpoint, scope, review_expires_at, })
}

///|
/// Approval evidence scoped to immutable originals. Every physical attempt
/// still needs current infer/egress/provider authority and journal entry.
pub struct ModelInvocationGrant {
  priv binding : ModelCheckpointBinding
  priv resolution_cid : String
  priv verified_resolution_cid : String
  priv verified_at : String
  priv expires_at : String
}

///|
/// Confirm the exact approved wrapper read back from the existing committed
/// journal. As with Checkpoint persistence, the storage owner supplies the
/// actual readback. This function owns no database, clock or signature keys.
pub fn confirm_model_invocation_grant(
  binding : ModelCheckpointBinding,
  persisted : PersistedCheckpoint,
  verified : VerifiedResolution,
  committed_verified_wire : String,
  at : String,
  limits : WireLimits,
) -> Result[ModelInvocationGrant, ResolutionIssue] {
  let checkpoint = binding.checkpoint
  if persisted.artifact.wire != checkpoint.wire ||
    verified.checkpoint_cid != checkpoint.checkpoint_cid ||
    committed_verified_wire != verified.wire {
    return Err(CheckpointBindingMismatch("committed_model_approval"))
  }
  if verified.decision != Approved {
    return Err(EvidenceMismatch("decision"))
  }
  model_invocation_grant_of(
    binding,
    verified.resolution_cid,
    verified.verified_resolution_cid,
    verified.verified_at,
    verified.wire,
    at,
    limits,
  )
}

///|
fn model_invocation_grant_of(
  binding : ModelCheckpointBinding,
  resolution_cid : String,
  verified_resolution_cid : String,
  verified_at : String,
  verified_wire : String,
  at : String,
  limits : WireLimits,
) -> Result[ModelInvocationGrant, ResolutionIssue] {
  let checkpoint = binding.checkpoint
  let approval = match resumed_approval(verified_wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // A VerifiedResolution may have been admitted for another kind. Recheck
  // the exact compatibility original rather than trusting its summary.
  guard parse_wire(verified_wire, limits) is Some(wrapper) &&
    @json.object_field(wrapper, "approval_evidence") is Some(evidence) &&
    @json.object_field(evidence, "compatibility_approval")
    is Some(compatibility) else {
    return Err(EvidenceRequired)
  }
  if string_field(evidence, "kind") != Some("model_invocation") ||
    string_field(compatibility, "prepared_invocation_cid") !=
    Some(@publication.model_invocation_scope_prepared_cid(binding.scope)) ||
    string_field(compatibility, "review_projection_cid") !=
    Some(checkpoint.checkpoint.review_projection_cid) ||
    approval.claims != ["invocation_scope_approved"] {
    return Err(EvidenceMismatch("model_invocation_scope"))
  }
  guard approval.expires_at is Some(approval_expires_at) else {
    return Err(EvidenceMismatch("expires_at"))
  }
  let mut expires_at = approval_expires_at
  for
    deadline in [
      binding.review_expires_at,
      @publication.model_invocation_scope_valid_until(binding.scope),
    ] {
    if deadline < expires_at {
      expires_at = deadline
    }
  }
  let grant = {
    binding,
    resolution_cid,
    verified_resolution_cid,
    verified_at,
    expires_at,
  }
  if !model_invocation_grant_current(grant, at) {
    return Err(DecisionOutsideWindow)
  }
  Ok(grant)
}

///|
pub fn model_invocation_grant_current(
  grant : ModelInvocationGrant,
  at : String,
) -> Bool {
  valid_timestamp(at) && grant.verified_at <= at && at < grant.expires_at
}

///|
pub fn model_invocation_grant_scope(
  grant : ModelInvocationGrant,
) -> @publication.BoundModelInvocationScope {
  grant.binding.scope
}

///|
pub fn model_invocation_grant_checkpoint_cid(
  grant : ModelInvocationGrant,
) -> String {
  grant.binding.checkpoint.checkpoint_cid
}

///|
pub fn model_invocation_grant_resolution_cid(
  grant : ModelInvocationGrant,
) -> String {
  grant.resolution_cid
}

///|
pub fn model_invocation_grant_expires_at(
  grant : ModelInvocationGrant,
) -> String {
  grant.expires_at
}

///|
pub fn model_invocation_grant_verified_resolution_cid(
  grant : ModelInvocationGrant,
) -> String {
  grant.verified_resolution_cid
}

///|
// Reconstruct the historical admission from the Host-authenticated wrapper.
// Exact re-sealing below checks every wrapper field and its canonical identity;
// this does not verify signatures or turn untrusted wire into authentication.
fn model_readback_admission(
  binding : ModelCheckpointBinding,
  wire : String,
  limits : WireLimits,
) -> (AdmittedResolution, String, String) raise ResolutionFailure {
  if !valid_limits(limits) {
    raise ResolutionFailed(ResolutionInvalidLimits)
  }
  guard parse_wire(wire, limits) is Some(wrapper) else {
    raise ResolutionFailed(ResolutionInvalidWire)
  }
  let resolution = object_of(wrapper, "resolution", "")
  let evidence = object_of(wrapper, "approval_evidence", "")
  let authorization = object_of(wrapper, "authorization_evidence", "")
  let attestation = object_of(wrapper, "host_attestation", "")
  guard wire_of(resolution, limits) is Some(resolution_wire) &&
    wire_of(evidence, limits) is Some(evidence_wire) else {
    raise ResolutionFailed(ResolutionEncoding)
  }
  let proof_preimage = match
    resolution_proof_preimage(resolution_wire, limits) {
    Ok(value) => value
    Err(issue) => raise ResolutionFailed(issue)
  }
  let key_id = text_of(authorization, "key_id", "authorization_evidence.")
  let reviewer_id = text_of(wrapper, "verified_reviewer_id", "")
  let authentication : HostAuthentication = {
    key_id,
    reviewer_id,
    // Model approvals bind the original PreparedInvocation, not a ReadAccess
    // authority scope. The scope is a checked CID used only for this profile.
    expected_authority_scope_cid: binding.checkpoint.checkpoint.required_artifact_cid,
    authority_context_cid: cid_field(wrapper, "authorization_context_cid", ""),
    policy_cid: cid_field(wrapper, "verified_by_policy_cid", ""),
    proof_preimage,
  }
  let admitted = admit_resolution_body(
    binding.checkpoint,
    resolution_wire,
    Some(evidence_wire),
    authentication,
    [{ key_id, reviewer_id, }],
    time_field(wrapper, "verified_at", ""),
    limits,
    Some(binding),
  )
  (
    admitted,
    text_of(attestation, "host_key_id", "host_attestation."),
    text_of(attestation, "signature", "host_attestation."),
  )
}

///|
/// Rebind the exact wrapper from the trusted private journal's original
/// authenticated atomic commit. Its established authentication and attestation
/// owner supplies provenance; canonical reconstruction here checks linkage, not
/// signatures. Arbitrary imported or rewritten storage bytes do not satisfy
/// this precondition.
pub fn confirm_model_invocation_grant_wire(
  binding : ModelCheckpointBinding,
  persisted : PersistedCheckpoint,
  committed_verified_wire : String,
  at : String,
  limits : WireLimits,
) -> Result[ModelInvocationGrant, ResolutionIssue] {
  try {
    let (admitted, key, signature) = model_readback_admission(
      binding, committed_verified_wire, limits,
    )
    let verified = match
      seal_verified_resolution(admitted, key, signature, limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    confirm_model_invocation_grant(
      binding, persisted, verified, committed_verified_wire, at, limits,
    )
  } catch {
    ResolutionFailed(issue) => Err(issue)
  }
}

///|
/// Rebind the exact wrapper issued by the established authenticated immediate
/// sealing owner. This checks linkage, not signatures, and creates no persisted
/// Checkpoint, deferred VerifiedResolution, or resume intent.
pub fn confirm_immediate_model_invocation_grant_wire(
  binding : ModelCheckpointBinding,
  sealed_verified_wire : String,
  at : String,
  limits : WireLimits,
) -> Result[ModelInvocationGrant, ResolutionIssue] {
  try {
    let (admitted, key, signature) = model_readback_admission(
      binding, sealed_verified_wire, limits,
    )
    let immediate = match
      seal_immediate_resolution({ admitted, }, key, signature, limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if immediate.wire != sealed_verified_wire {
      return Err(CheckpointBindingMismatch("sealed_model_approval"))
    }
    if immediate.decision != Approved {
      return Err(EvidenceMismatch("decision"))
    }
    model_invocation_grant_of(
      binding,
      immediate.resolution_cid,
      immediate.verified_resolution_cid,
      immediate.verified_at,
      immediate.wire,
      at,
      limits,
    )
  } catch {
    ResolutionFailed(issue) => Err(issue)
  }
}
