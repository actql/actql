///|
// Two existing Reviewer artifacts share the same original subject/key/use
// Owner. Neither arm accepts arbitrary bytes or substitutes another preimage.
priv enum NativeLocalReviewerOriginalProof {
  ResolutionOriginal(@checkpoint.PreparedResolutionProof)
  ApprovalOriginal(@checkpoint.PreparedEffectApprovalProof)
}

///|
priv enum NativeLocalReviewerOriginalProofKind {
  ResolutionOriginalKind
  ApprovalOriginalKind
}

///|
fn NativeLocalReviewerOriginalProof::checkpoint(
  self : NativeLocalReviewerOriginalProof,
) -> @checkpoint.SealedCheckpoint {
  match self {
    ResolutionOriginal(value) => value.checkpoint()
    ApprovalOriginal(value) => value.checkpoint()
  }
}

///|
fn NativeLocalReviewerOriginalProof::actor(
  self : NativeLocalReviewerOriginalProof,
) -> String {
  match self {
    ResolutionOriginal(value) => value.actor()
    ApprovalOriginal(value) => value.actor()
  }
}

///|
fn NativeLocalReviewerOriginalProof::preimage(
  self : NativeLocalReviewerOriginalProof,
) -> String {
  match self {
    ResolutionOriginal(value) => value.preimage()
    ApprovalOriginal(value) => value.preimage()
  }
}

///|
fn NativeLocalReviewerOriginalProof::decision(
  self : NativeLocalReviewerOriginalProof,
) -> @checkpoint.ResolutionDecision {
  match self {
    ResolutionOriginal(value) => value.decision()
    ApprovalOriginal(_) => @checkpoint.Approved
  }
}

///|
fn NativeLocalReviewerOriginalProof::seal(
  self : NativeLocalReviewerOriginalProof,
  key_id : String,
  signature : String,
) -> Result[String, @checkpoint.ResolutionIssue] {
  match self {
    ResolutionOriginal(value) =>
      @checkpoint.seal_prepared_resolution_proof(value, key_id, signature)
    ApprovalOriginal(value) =>
      @checkpoint.seal_prepared_effect_approval_proof(value, key_id, signature).map(value => {
          value.0
        },
      )
  }
}

///|
/// Same original initial key and current registered Reviewer. This only
/// prepares the typed approval proof; it issues no grant or physical use.
pub fn NativeLocalInitialReviewerSigningKey::prepare_approval_proof_materials(
  self : NativeLocalInitialReviewerSigningKey,
  reviewer : NativeLocalEffectReviewerBinding,
  unsigned_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[
  NativeLocalReviewerProofMaterials,
  NativeLocalReviewerProofMaterialsIssue,
] {
  prepare_local_reviewer_original_proof_materials(
    InitialReviewerKey(self),
    reviewer,
    unsigned_wire,
    limits,
    ApprovalOriginalKind,
  )
}
