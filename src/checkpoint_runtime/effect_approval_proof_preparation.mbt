///|
/// Typed unsigned `actql-approval-attestation/0.1` for the original Checkpoint.
/// This is subject/claim DATA, not authentication, permission or a signing use.
struct PreparedEffectApprovalProof {
  checkpoint : SealedCheckpoint
  body : @json.CanonicalValue
  actor : String
  preimage : String
  limits : WireLimits
}

///|
pub fn prepare_effect_approval_proof(
  checkpoint : SealedCheckpoint,
  unsigned_wire : String,
  expected_authority_scope_cid : String,
  limits : WireLimits,
) -> Result[PreparedEffectApprovalProof, ResolutionIssue] {
  if !valid_limits(limits) {
    return Err(ResolutionInvalidLimits)
  }
  if checkpoint.checkpoint.kind != EffectSet ||
    !valid_cid(expected_authority_scope_cid) {
    return Err(EvidenceMismatch("authority_scope_cid"))
  }
  let value = match parse_wire(unsigned_wire, limits) {
    Some(value) => value
    None => return Err(ResolutionInvalidWire)
  }
  try {
    check_effect_approval_subject(
      value,
      checkpoint.checkpoint,
      expected_authority_scope_cid,
      limits,
      signed=false,
    )
    check_approval_review_projection(
      value,
      checkpoint.checkpoint,
      "approval_evidence.compatibility_approval.",
    )
    let actor = text_of(value, "approver", "")
    ignore(time_field(value, "approved_at", ""))
    let preimage = match cid_of(value, limits) {
      Some(value) => value
      None => return Err(ResolutionEncoding)
    }
    Ok({ checkpoint, body: value, actor, preimage, limits, })
  } catch {
    ResolutionFailed(issue) => Err(issue)
  }
}

///|
pub fn PreparedEffectApprovalProof::checkpoint(
  self : PreparedEffectApprovalProof,
) -> SealedCheckpoint {
  self.checkpoint
}

///|
pub fn PreparedEffectApprovalProof::actor(
  self : PreparedEffectApprovalProof,
) -> String {
  self.actor
}

///|
pub fn PreparedEffectApprovalProof::preimage(
  self : PreparedEffectApprovalProof,
) -> String {
  self.preimage
}

///|
/// Attach actual external proof bytes using the SAME closed Reviewer-proof
/// codec, then emit the existing approval-evidence envelope and its identity.
/// Signature/current authority and Resolution admission remain separate.
pub fn seal_prepared_effect_approval_proof(
  prepared : PreparedEffectApprovalProof,
  key_id : String,
  signature : String,
) -> Result[(String, String), ResolutionIssue] {
  let approval = match
    seal_prepared_reviewer_proof_body(
      prepared.body,
      key_id,
      signature,
      "attestation_cid",
      prepared.limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let artifact = prepared.checkpoint
  let evidence = match
    canonical_of(
      Json::object({
        "version": Json::string(EVIDENCE_VERSION),
        "kind": Json::string(checkpoint_kind_token(artifact.checkpoint.kind)),
        "checkpoint_cid": Json::string(artifact.checkpoint_cid),
        "review_projection_cid": Json::string(
          artifact.checkpoint.review_projection_cid,
        ),
        "compatibility_approval": to_json(approval),
      }),
      prepared.limits,
    ) {
    Some(value) => value
    None => return Err(ResolutionEncoding)
  }
  match
    (wire_of(evidence, prepared.limits), cid_of(evidence, prepared.limits)) {
    (Some(wire), Some(cid)) => Ok((wire, cid))
    _ => Err(ResolutionEncoding)
  }
}

///|
/// Borrow the already structurally admitted Approval proof for the Host's
/// actual same-key verification. This does not authenticate a signature or
/// convert Resolution admission into cryptographic approval evidence.
pub fn AdmittedResolution::approval_proof_materials(
  self : AdmittedResolution,
  limits : WireLimits,
) -> Result[(String, String, String)?, ResolutionIssue] {
  if self.decision == Rejected {
    return Ok(None)
  }
  if !valid_limits(limits) {
    return Err(ResolutionInvalidLimits)
  }
  try {
    let evidence = object_of(self.body, "approval_evidence", "")
    Ok(Some(approval_evidence_proof_materials(evidence, limits)))
  } catch {
    ResolutionFailed(issue) => Err(issue)
  }
}

///|
fn approval_evidence_proof_materials(
  evidence : @json.CanonicalValue,
  limits : WireLimits,
) -> (String, String, String) raise ResolutionFailure {
  let approval = object_of(
    evidence, "compatibility_approval", "approval_evidence.",
  )
  let proof = object_of(
    approval, "proof", "approval_evidence.compatibility_approval.",
  )
  let key = proof_key(
    proof, "key_id", "approval_evidence.compatibility_approval.proof.",
  )
  let signature = text_of(
    proof, "signature", "approval_evidence.compatibility_approval.proof.",
  )
  let identity = if string_field(evidence, "kind") == Some("effect_set") {
    "attestation_cid"
  } else {
    "run_scope_approval_cid"
  }
  let preimage = unsigned_cid(approval, identity, "proof", limits)
  (key, preimage, signature)
}

///|
/// The already prepared Resolution's exact required Approval evidence, using
/// the SAME Checkpoint/claim/actor/authority admission as the final wrapper.
/// These proof materials authenticate nothing; a caller must join the actual
/// stored signature/use and verify the current original key independently.
pub fn PreparedResolutionProof::approval_proof_materials(
  self : PreparedResolutionProof,
  evidence_wire : String,
  authority_scope_cid : String,
) -> Result[(String, String, String), ResolutionIssue] {
  if self.decision != Approved || self.checkpoint.checkpoint.kind != EffectSet {
    return Err(EvidenceRequired)
  }
  try {
    let identity = cid_field(self.body, "approval_evidence_cid", "")
    let evidence = check_evidence(
      evidence_wire,
      identity,
      self.checkpoint,
      self.actor,
      authority_scope_cid,
      self.limits,
      None,
    )
    Ok(approval_evidence_proof_materials(evidence, self.limits))
  } catch {
    ResolutionFailed(issue) => Err(issue)
  }
}
