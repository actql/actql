///|
priv struct NativeLocalReviewerProofSnapshot {
  artifact : @checkpoint.SealedCheckpoint
  revision : Int64
  cancellation_requested : Bool
  state : @checkpoint.RunStateView
  reported_unknown_effect_count : Int
  settlement_only : Bool
} derive(Eq)

///|
/// Original subject and candidate proof metadata in the existing Host assembly.
/// This holds no secret body, grant, credential ordinal or signing permission.
/// The full Checkpoint/unsigned body remain private: this is not an Approval
/// disclosure API and does not replace the existing material disclosure Owner.
struct NativeLocalReviewerProofMaterials {
  key : NativeLocalReviewerProofKey
  reviewer : NativeLocalEffectReviewerBinding
  registration : @effect_resolution.NativeEffectReviewerRegistration
  original : NativeLocalReviewerProofSnapshot
  proof : NativeLocalReviewerOriginalProof
}

///|
pub(all) enum NativeLocalReviewerProofMaterialsIssue {
  ProofUnavailable
  ProofKey(NativeLocalSigningOriginalIssue)
  ProofOriginal(NativeClientRunJournalIssue)
  ProofBody(@checkpoint.ResolutionIssue)
}

///|
// Only the enclosing opaque current binding calls this reader. It supplies no
// Allow. Current Reviewer/key and original Client RunRead are checked outside
// this transaction, because read_current itself owns a journal transaction.
fn local_reviewer_proof_snapshot(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  expected_run : String,
  expected_checkpoint : String,
) -> Result[NativeLocalReviewerProofSnapshot, NativeClientRunJournalIssue] {
  journal.transaction(() => {
    local_reviewer_proof_snapshot_locked(
      journal, request, expected_run, expected_checkpoint,
    )
  })
}

///|
// Same record validator under an already-owned journal TX. It emits only the
// small immutable snapshot; no second codec, permission or transaction exists.
fn local_reviewer_proof_snapshot_locked(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  expected_run : String,
  expected_checkpoint : String,
) -> Result[NativeLocalReviewerProofSnapshot, NativeClientRunJournalIssue] {
  // Cold retained reads admit the complete checkpoint in read_checkpoint_record;
  // the existing operation/transaction slot reuses only that admitted record,
  // with its row bytes/revision and normal invalidation checks. Keep its opaque
  // sealed artifact here instead of parsing the same immutable wire again.
  let record = match journal.retained(request) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  if @host.client_request_identity_relation(record.request, request) !=
    @host.SameRequest ||
    @publication.publication_contract_identity(record.definition) !=
    expected_run {
    return Err(ForeignRun)
  }
  guard record.checkpoint is Some(checkpoint) else {
    return Err(Checkpoint(NeedsOriginalContinuation))
  }
  guard @publication.run_definition_run_id(record.definition) is Ok(run_id) &&
    checkpoint.artifact.checkpoint_cid == expected_checkpoint &&
    checkpoint.artifact.checkpoint.kind == @checkpoint.EffectSet &&
    checkpoint.artifact.checkpoint.run_id() == Some(run_id) &&
    checkpoint.artifact.checkpoint.run_definition_cid() == Some(expected_run) &&
    checkpoint.state.run_id == run_id else {
    return Err(ForeignRun)
  }
  // These are captured facts, not an eligibility decision. Unknown Effects,
  // cancellation and settlement do not become a successful signing use.
  Ok({
    artifact: checkpoint.artifact,
    revision: record.revision,
    cancellation_requested: record.cancellation_requested,
    state: checkpoint.state,
    reported_unknown_effect_count: checkpoint.unknown_effects.length(),
    settlement_only: checkpoint.settlement_only,
  })
}

///|
/// Bind only the exact journal-owned Checkpoint to the candidate unsigned
/// Resolution. No caller Checkpoint/CID, issuer public-key CID, key generation
/// or current Boolean is accepted. Neither this preparation nor its preimage
/// can acquire a signing use or authorize resolution/commit.
pub fn NativeLocalSigningKeyOriginal::prepare_reviewer_proof_materials(
  self : NativeLocalSigningKeyOriginal,
  reviewer : NativeLocalEffectReviewerBinding,
  unsigned_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[
  NativeLocalReviewerProofMaterials,
  NativeLocalReviewerProofMaterialsIssue,
] {
  prepare_local_reviewer_proof_materials(
    ConfiguredReviewerKey(self),
    reviewer,
    unsigned_wire,
    limits,
  )
}

///|
fn prepare_local_reviewer_proof_materials(
  key : NativeLocalReviewerProofKey,
  reviewer : NativeLocalEffectReviewerBinding,
  unsigned_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[
  NativeLocalReviewerProofMaterials,
  NativeLocalReviewerProofMaterialsIssue,
] {
  prepare_local_reviewer_original_proof_materials(
    key,
    reviewer,
    unsigned_wire,
    limits,
    ResolutionOriginalKind,
  )
}

///|
fn prepare_local_reviewer_original_proof_materials(
  key : NativeLocalReviewerProofKey,
  reviewer : NativeLocalEffectReviewerBinding,
  unsigned_wire : String,
  limits : @checkpoint.WireLimits,
  kind : NativeLocalReviewerOriginalProofKind,
) -> Result[
  NativeLocalReviewerProofMaterials,
  NativeLocalReviewerProofMaterialsIssue,
] {
  let registration = match key.read_current_reviewer(reviewer) {
    Ok(value) => value
    Err(issue) => return Err(ProofKey(issue))
  }
  let original = match
    local_reviewer_proof_snapshot(
      reviewer.host.journal,
      reviewer.request,
      reviewer.original.run_definition_cid,
      reviewer.original.checkpoint_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ProofOriginal(issue))
  }
  let proof = match kind {
    ResolutionOriginalKind =>
      match
        @checkpoint.prepare_resolution_proof(
          original.artifact,
          unsigned_wire,
          limits,
        ) {
        Ok(value) => ResolutionOriginal(value)
        Err(issue) => return Err(ProofBody(issue))
      }
    ApprovalOriginalKind =>
      match
        @checkpoint.prepare_effect_approval_proof(
          original.artifact,
          unsigned_wire,
          registration.approval_authority_scope_cid,
          limits,
        ) {
        Ok(value) => ApprovalOriginal(value)
        Err(issue) => return Err(ProofBody(issue))
      }
  }
  if proof.actor() != registration.reviewer_id {
    return Err(ProofUnavailable)
  }
  let materials : NativeLocalReviewerProofMaterials = {
    key,
    reviewer,
    registration,
    original,
    proof,
  }
  materials.require_current().map(_ => materials)
}

///|
/// Re-read current authorization/key custody and the same original journal
/// facts. No cached Allow, fresh Checkpoint or current compilation is used.
/// This is a read consistency fence, not signing eligibility or permission.
pub fn NativeLocalReviewerProofMaterials::require_current(
  self : NativeLocalReviewerProofMaterials,
) -> Result[Unit, NativeLocalReviewerProofMaterialsIssue] {
  let reviewer = self.reviewer
  let before = match self.key.read_current_reviewer(reviewer) {
    Ok(value) => value
    Err(issue) => return Err(ProofKey(issue))
  }
  if before != self.registration ||
    self.proof.actor() != before.reviewer_id ||
    self.proof.checkpoint() != self.original.artifact {
    return Err(ProofUnavailable)
  }
  let actual = match
    local_reviewer_proof_snapshot(
      reviewer.host.journal,
      reviewer.request,
      reviewer.original.run_definition_cid,
      reviewer.original.checkpoint_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ProofOriginal(issue))
  }
  if actual != self.original {
    return Err(ProofOriginal(Checkpoint(StaleRevision)))
  }
  match (self.key, reviewer.approval_scope) {
    (InitialReviewerKey(key), SavedApproval(_)) if key.original.original_read
      is Some(_) =>
      // Only the trusted journal snapshot separated this SAME registration
      // read from here. Keep its original projection instead of running the
      // complete clock/Account/Checkpoint traversal twice. The final metadata
      // read below still samples time, checks RunRead/revision/cancellation,
      // and finishes this same physical key after its last callback.
      match self.key.finish_original_projection() {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    _ =>
      match self.key.read_current_reviewer(reviewer) {
        Ok(value) if value == before => ()
        Ok(_) => return Err(ProofUnavailable)
        Err(issue) => return Err(ProofKey(issue))
      }
  }
  // The existing metadata Owner performs its own current RunRead before/after
  // the final original read. A same-Checkpoint callback observation cannot
  // hide an intervening cancellation or another control revision.
  match
    reviewer.host.lookup_submitted_checkpoint_metadata(
      reviewer.crypto,
      reviewer.principal,
      reviewer.connection,
      reviewer.reference,
      reviewer.request,
      (reviewer.now)(),
    ) {
    Ok(Some(value)) if value.revision == self.original.revision &&
      value.cancellation_requested == self.original.cancellation_requested &&
      value.state == self.original.state &&
      value.checkpoint_cid == self.original.artifact.checkpoint_cid &&
      value.run_definition_cid == reviewer.original.run_definition_cid =>
      // The last clock/RunRead callback may replace the selected key or Host
      // file. Recheck the same physical originals without another callback.
      self.key.finish_original_projection()
    Ok(_) => Err(ProofOriginal(Checkpoint(StaleRevision)))
    Err(Journal(issue)) => Err(ProofOriginal(issue))
    Err(_) => Err(ProofUnavailable)
  }
}

///|
/// Exact existing Checkpoint-owned unsigned CID text only. Approval body
/// disclosure, grant issuance, credential use and signature require their
/// separate existing Owners and original/current facts.
pub fn NativeLocalReviewerProofMaterials::preimage(
  self : NativeLocalReviewerProofMaterials,
) -> Result[String, NativeLocalReviewerProofMaterialsIssue] {
  self.require_current().map(_ => self.proof.preimage())
}

///|
/// Original Run revision, cancellation, state, reported Checkpoint unknown-count
/// and settlement facts. The reported count does not summarize all Effect
/// Ledger responsibilities and zero never proves settlement.
/// These are never an inferred permission or a completion result.
pub fn NativeLocalReviewerProofMaterials::original_facts(
  self : NativeLocalReviewerProofMaterials,
) -> Result[
  (Int64, Bool, @checkpoint.RunStateView, Int, Bool),
  NativeLocalReviewerProofMaterialsIssue,
] {
  self
  .require_current()
  .map(_ => {
    (
      self.original.revision,
      self.original.cancellation_requested,
      self.original.state,
      self.original.reported_unknown_effect_count,
      self.original.settlement_only,
    )
  })
}
