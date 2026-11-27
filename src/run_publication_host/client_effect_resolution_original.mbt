///|
/// A protected registration must be selected by the current Host. Neither
/// its label nor equal public data proves a current key or approval.
pub(all) struct ClientEffectResolutionReviewer {
  registration : @checkpoint.ReviewerAuthority
  policy_cid : String
}

///|
pub(all) enum ClientEffectResolutionOriginalIssue {
  InvalidOriginal
  ReviewerRefused
  Resolution(@checkpoint.ResolutionIssue)
  State(@checkpoint.RunStateWireIssue)
  Resume(@checkpoint.ResumeIssue)
  Encoding
}

///|
/// One candidate signed answer's existing two proof coordinates. Only the
/// trusted Host's exact physical verifier can advance this original.
pub struct ClientEffectResolutionProofChallenge {
  review : ClientEffectSavedReviewConfirmation
  admitted : @checkpoint.AdmittedResolution
  at : String
  actor : String
  resolution_proof : (String, String, String)
  approval_proof : (String, String, String)?
}

///|
/// Retain the actual authenticated Review with this prepared decision before
/// the independent Host attestation role acquires its key.
pub struct ClientEffectResolutionAttestationOriginal {
  review : ClientEffectSavedReviewConfirmation
  admitted : @checkpoint.AdmittedResolution
  at : String
}

///|
pub struct ClientEffectResolutionJournalDecision {
  before : ClientJournalPhysicalRow
  body : Bytes
  verified : @checkpoint.VerifiedResolution
  request : ClientRequestIdentity
  definition : @publication.PublicationContract
}

///|
fn client_effect_signed_proof(
  wire : String,
  limits : @checkpoint.WireLimits,
) -> (String, String, String, String)? {
  let bytes = @utf8.encode(wire)
  guard bytes.length() <= limits.max_wire_bytes &&
    @checkpoint.resolution_proof_preimage(wire, limits) is Ok(preimage) &&
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    })
    is Ok(source) &&
    @decode.admit(source, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_wire_bytes,
      max_total_string_bytes: limits.max_wire_bytes,
    })
    is Ok(cursor) &&
    @decode.open_object(cursor) is Ok(fields) &&
    client_checkpoint_text(fields, "actor") is Some(actor) &&
    @decode.required(fields, "proof") is Ok(raw_proof) &&
    @decode.closed_object(raw_proof, ["scheme", "key_id", "signature"])
    is Ok(proof) &&
    client_checkpoint_text(proof, "scheme") == Some("ed25519-v1") &&
    client_checkpoint_text(proof, "key_id") is Some(key) &&
    client_checkpoint_text(proof, "signature") is Some(signature) else {
    return None
  }
  Some((actor, key, preimage, signature))
}

///|
/// Verify both existing reviewer proof preimages under the same original
/// registration and current waiting checkpoint. No Host key is used here.
pub fn prepare_client_effect_resolution_proof_challenge(
  review : ClientEffectSavedReviewConfirmation,
  resolution_wire : String,
  approval_evidence_wire : String?,
  selected : ClientEffectResolutionReviewer,
  at : String,
  current : () -> Bool,
  limits : @checkpoint.WireLimits,
) -> Result[
  ClientEffectResolutionProofChallenge,
  ClientEffectResolutionOriginalIssue,
] {
  let waiting = review.reference.waiting
  let checkpoint = waiting.checkpoint.artifact
  let authority = selected.registration
  guard current() &&
    @checkpoint.checkpoint_expired_at(checkpoint, at) == Ok(false) &&
    valid_client_request_cid(selected.policy_cid) &&
    client_effect_signed_proof(resolution_wire, limits)
    is Some((actor, key, preimage, signature)) &&
    actor == authority.reviewer_id &&
    key == authority.key_id &&
    current() else {
    return Err(ReviewerRefused)
  }
  let authentication : @checkpoint.HostAuthentication = {
    key_id: key,
    reviewer_id: actor,
    expected_authority_scope_cid: client_request_authority_scope_cid(
      waiting.run.request,
    ),
    authority_context_cid: waiting.checkpoint.binding.authorization_context_cid,
    policy_cid: selected.policy_cid,
    proof_preimage: preimage,
  }
  let admitted = match
    @checkpoint.admit_checkpoint_resolution(
      checkpoint,
      resolution_wire,
      approval_evidence_wire,
      authentication,
      [authority],
      at,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resolution(issue))
  }
  let approval_proof = match admitted.approval_proof_materials(limits) {
    Err(issue) => return Err(Resolution(issue))
    Ok(Some((approval_key, _, _))) if key != approval_key =>
      return Err(ReviewerRefused)
    Ok(value) => value
  }
  if !current() {
    return Err(ReviewerRefused)
  }
  Ok({
    review,
    admitted,
    at,
    actor,
    resolution_proof: (key, preimage, signature),
    approval_proof,
  })
}

///|
/// Read the candidate's exact existing unsigned-CID proof coordinates. This
/// is DATA so the physical Reviewer verifier can verify both signatures.
pub fn ClientEffectResolutionProofChallenge::proofs(
  self : ClientEffectResolutionProofChallenge,
) -> (String, (String, String, String), (String, String, String)?) {
  (self.actor, self.resolution_proof, self.approval_proof)
}

///|
/// Restate currentness before and after each physical verification. A refused
/// signature retains this challenge and cannot borrow the Host signing role.
pub fn ClientEffectResolutionProofChallenge::verified(
  self : ClientEffectResolutionProofChallenge,
  current : () -> Bool,
  verify : (String, String, String) -> Bool,
) -> Result[
  ClientEffectResolutionAttestationOriginal,
  ClientEffectResolutionOriginalIssue,
] {
  let (key, cid, signature) = self.resolution_proof
  if !current() || !verify(key, cid, signature) || !current() {
    return Err(ReviewerRefused)
  }
  if self.approval_proof is Some((key, cid, signature)) {
    if !verify(key, cid, signature) || !current() {
      return Err(ReviewerRefused)
    }
  }
  Ok({ review: self.review, admitted: self.admitted, at: self.at, })
}

///|
/// The only CID text the independent Host attestation role may sign here.
pub fn ClientEffectResolutionAttestationOriginal::attestation_preimage(
  self : ClientEffectResolutionAttestationOriginal,
) -> String {
  self.admitted.attestation_preimage
}

///|
/// Produce the exact successor candidate after Host signing and current
/// reobservation. The caller retains this once across the actual Store CAS
/// and separately confirms the physical successor after COMMIT.
pub fn ClientEffectResolutionAttestationOriginal::prepare_journal_decision(
  self : ClientEffectResolutionAttestationOriginal,
  host_key : String,
  signature : String,
  current : () -> Bool,
  limits : @checkpoint.WireLimits,
  before_decode? : ((ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
  before_encode? : ((Int, Int, Int) -> Result[Unit, ClientJournalEncodingIssue])? = None,
) -> Result[
  ClientEffectResolutionJournalDecision,
  ClientEffectResolutionOriginalIssue,
] {
  let original = self.review.reference.waiting
  let checkpoint = original.checkpoint
  guard current() &&
    client_saved_submission_run_row(original.submission) is Some(before) &&
    before.revision == 3L &&
    @checkpoint.checkpoint_expired_at(checkpoint.artifact, self.at) == Ok(false) else {
    return Err(InvalidOriginal)
  }
  let verified = match
    @checkpoint.seal_verified_resolution(
      self.admitted,
      host_key,
      signature,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resolution(issue))
  }
  guard @checkpoint.decide_resolution_commit(
      checkpoint.artifact,
      @checkpoint.Open,
      verified,
    )
    is @checkpoint.CommitResolution &&
    @checkpoint.resolution_effect(
      checkpoint.artifact,
      verified.decision,
      unknown_effects=checkpoint.unknown_effects,
    )
    is @checkpoint.MoveRun(next) &&
    @checkpoint.run_transition_allowed(checkpoint.state.status, next) else {
    return Err(InvalidOriginal)
  }
  let state_wire = if verified.decision == @checkpoint.Approved {
    @checkpoint.issue_lifecycle_run_state(
      checkpoint.state.run_id,
      next,
      self.at,
      checkpoint.declared_results,
      limits,
    )
  } else {
    @checkpoint.issue_waiting_exit_run_state(
      checkpoint.state.run_id,
      self.at,
      checkpoint.declared_results,
      checkpoint.unknown_effects,
      limits,
    )
  }
  let state = match
    state_wire.bind(wire => @checkpoint.admit_run_state_wire(wire, limits)) {
    Ok(state) => state
    Err(issue) => return Err(State(issue))
  }
  let successor : ClientCheckpointJournalRecord = {
    ..checkpoint,
    updated_at: self.at,
    state,
    resolution_cid: Some(verified.resolution_cid),
    verified_wire: Some(verified.wire),
    resume_intent_id: verified.resume_intent_id,
    resume_intent: verified.resume_intent_id.map(_ => {
      state: @checkpoint.ResumePending,
      generation: 0L,
      claimant: "",
      lease_expires_ms: 0L,
    }),
  }
  guard client_checkpoint_journal_row_body(successor) is Ok(checkpoint_wire) &&
    decode_client_run_journal_row_with_retained_identity(
      before.body,
      original.run.request,
      original.run.definition,
      require_retained_identity=true,
      before_construction=before_decode,
    )
    is Ok((run, policy, observation)) &&
    client_run_journal_row_body(
      { ..run, checkpoint: Some(checkpoint_wire), },
      local_run_policy_originals=policy,
      run_observation_originals=observation,
      measure_construction=before_encode is Some(_),
      before_construction=before_encode,
    )
    is Ok(body) &&
    current() else {
    return Err(Encoding)
  }
  Ok({
    before,
    body,
    verified,
    request: run.request,
    definition: run.definition,
  })
}

///|
/// Borrow the original waiting row and its candidate in the same Journal CAS.
pub fn ClientEffectResolutionJournalDecision::rows(
  self : ClientEffectResolutionJournalDecision,
) -> (ClientJournalPhysicalRow, Bytes) {
  (self.before, self.body)
}

///|
/// Exact generation and body confirmation in the original Store reader.
pub fn ClientEffectResolutionJournalDecision::confirmed(
  self : ClientEffectResolutionJournalDecision,
  actual : ClientJournalPhysicalRow,
) -> Bool {
  actual.key == self.before.key &&
  actual.revision == self.before.revision + 1L &&
  actual.body == self.body
}

///|
/// Project the committed answer only for the exact original successor. The
/// physical caller must separately confirm its Read returned before disclosure.
pub fn ClientEffectResolutionJournalDecision::committed_coordinates(
  self : ClientEffectResolutionJournalDecision,
  actual : ClientJournalPhysicalRow,
) -> (String, String, String)? {
  if !self.confirmed(actual) {
    return None
  }
  let decision = match self.verified.decision {
    @checkpoint.Approved => "approved"
    @checkpoint.Rejected => "rejected"
  }
  Some((self.verified.checkpoint_cid, self.verified.resolution_cid, decision))
}

///|
/// A candidate claim belongs to the exact confirmed decision and one
/// increasing lease generation. Its successor requires its own physical ACK.
pub struct ClientEffectResolutionResumeClaim {
  before : ClientJournalPhysicalRow
  body : Bytes
  claim : @checkpoint.ResumeClaim
  verified : @checkpoint.VerifiedResolution
  lease_expires_ms : Int64
  settlement_only : Bool
}

///|
pub fn ClientEffectResolutionJournalDecision::prepare_resume_claim(
  self : ClientEffectResolutionJournalDecision,
  actual : ClientJournalPhysicalRow,
  claimant : String,
  now_ms : Int64,
  lease_ms : Int64,
  current : @checkpoint.ResumeBinding,
  still_current : () -> Bool,
  before_decode? : ((ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
  before_encode? : ((Int, Int, Int) -> Result[Unit, ClientJournalEncodingIssue])? = None,
) -> Result[
  ClientEffectResolutionResumeClaim,
  ClientEffectResolutionOriginalIssue,
] {
  guard self.verified.decision == @checkpoint.Approved &&
    self.confirmed(actual) &&
    still_current() &&
    decode_client_run_journal_row_with_retained_identity(
      actual.body,
      self.request,
      self.definition,
      require_retained_identity=true,
      before_construction=before_decode,
    )
    is Ok((run, policy, observation)) &&
    run.checkpoint is Some(wire) &&
    decode_client_checkpoint_journal_row(
      wire,
      run.definition,
      client_checkpoint_journal_limits(),
    )
    is Ok(checkpoint) &&
    checkpoint.state.status == @publication.Resuming &&
    checkpoint.resolution_cid == Some(self.verified.resolution_cid) &&
    checkpoint.verified_wire == Some(self.verified.wire) &&
    checkpoint.resume_intent_id == self.verified.resume_intent_id &&
    checkpoint.resume_intent is Some(intent) &&
    intent.state == @checkpoint.ResumePending &&
    intent.generation == 0L else {
    return Err(InvalidOriginal)
  }
  let action = match
    @checkpoint.decide_effect_resume_claim(
      intent,
      claimant,
      now_ms,
      lease_ms,
      checkpoint.binding,
      current,
      checkpoint.settlement_only || run.cancellation_requested(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resume(issue))
  }
  let (generation, expires, settlement_only) = match action {
    @checkpoint.ClaimIntent(generation, expires) => (generation, expires, false)
    @checkpoint.ClaimSettlement(generation, expires) =>
      (generation, expires, true)
    _ => return Err(InvalidOriginal)
  }
  let claim : @checkpoint.ResumeClaim = { claimant, generation, }
  guard client_checkpoint_journal_row_body({
      ..checkpoint,
      resume_intent: Some({
        state: @checkpoint.ResumeClaimed,
        generation,
        claimant,
        lease_expires_ms: expires,
      }),
      settlement_only,
    })
    is Ok(checkpoint_wire) &&
    client_run_journal_row_body(
      { ..run, checkpoint: Some(checkpoint_wire), },
      local_run_policy_originals=policy,
      run_observation_originals=observation,
      measure_construction=before_encode is Some(_),
      before_construction=before_encode,
    )
    is Ok(body) &&
    still_current() else {
    return Err(Encoding)
  }
  Ok({
    before: actual,
    body,
    claim,
    verified: self.verified,
    lease_expires_ms: expires,
    settlement_only,
  })
}

///|
/// Borrow the confirmed resolution row and the exact first claim candidate.
pub fn ClientEffectResolutionResumeClaim::rows(
  self : ClientEffectResolutionResumeClaim,
) -> (ClientJournalPhysicalRow, Bytes) {
  (self.before, self.body)
}

///|
/// The candidate's selected lease role. It supplies no physical acceptance.
pub fn ClientEffectResolutionResumeClaim::permits_application(
  self : ClientEffectResolutionResumeClaim,
) -> Bool {
  !self.settlement_only
}

///|
/// A matching physical successor is required before borrowing this dispatch
/// generation. Settlement-only custody confers no permission to apply.
pub fn ClientEffectResolutionResumeClaim::confirmed(
  self : ClientEffectResolutionResumeClaim,
  actual : ClientJournalPhysicalRow,
) -> @checkpoint.ResumeClaim? {
  if self.settlement_only ||
    actual.key != self.before.key ||
    actual.revision != self.before.revision + 1L ||
    actual.body != self.body {
    None
  } else {
    Some(self.claim)
  }
}

///|
/// Reobserve the affected ordinary rows under this proof's same waiting
/// original. A new body, revision, locator or witness needs a new admission.
pub fn[E] ClientEffectResolutionProofChallenge::require_waiting(
  self : ClientEffectResolutionProofChallenge,
  read : (String, String, Int) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
  observed_run? : ClientJournalPhysicalRow? = None,
) -> Result[Unit, E] {
  let waiting = self.review.reference.waiting
  let submitted = client_saved_submission_row(waiting.submission)
  let artifact = waiting.checkpoint.artifact
  let checkpoint = artifact.checkpoint
  let scope = client_request_scope_cid(waiting.run.request)
  let locator = client_checkpoint_locator_key(
    client_request_authority_scope_cid(waiting.run.request),
    checkpoint.checkpoint_id,
  )
  guard client_saved_submission_run_row(waiting.submission) is Some(run) &&
    client_checkpoint_locator_body(waiting.run.request, artifact)
    is Ok(locator_body) &&
    client_effect_ledger_base_witness(
      waiting.run.request,
      waiting.run.definition,
      waiting.checkpoint,
    )
    is Some(witness) else {
    return Err(custody_lost)
  }
  let expected_run = observed_run.unwrap_or(run)
  guard expected_run.key == run.key &&
    (
      expected_run.revision == run.revision ||
      expected_run.revision == run.revision + 1L ||
      expected_run.revision == run.revision + 2L
    ) else {
    return Err(custody_lost)
  }
  let expected_rows : Array[(String, ClientJournalPhysicalRow)] = [
    ("client_submitted_intents", submitted),
    ("client_runs", expected_run),
    (
      "client_checkpoint_id_index",
      { key: locator, revision: 0L, body: locator_body, },
    ),
    ("client_effect_custody", { key: scope, revision: 0L, body: witness, }),
  ]
  for (table, expected) in expected_rows {
    match read(table, expected.key, expected.body.length()) {
      Ok(Some(actual)) if actual.key == expected.key &&
        actual.revision == expected.revision &&
        actual.body == expected.body => ()
      Ok(_) => return Err(custody_lost)
      Err(issue) => return Err(issue)
    }
  }
  Ok(())
}
