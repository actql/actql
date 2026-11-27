///|
/// A process-local handle to an existing common resume claim. It is not a
/// Provider-send capability. Every protected mutation must recheck its fence
/// together with the original Effect Ledger row in the same transaction.
struct NativeClientEffectResumeClaim {
  journal : NativeClientRunJournal
  request : @host.ClientRequestIdentity
  checkpoint_cid : String
  resolution_cid : String
  intent_id : String
  claim : @checkpoint.ResumeClaim
  original_lease_expires_ms : Int64
  // The SAME permission parsed after cryptographic admission above. Retain
  // it on this claim rather than reparsing its immutable wire per target/IO.
  approval : @checkpoint.ResumedApproval
}

///|
pub enum NativeClientEffectResumeAction {
  Claimed(NativeClientEffectResumeClaim)
  SettlementOnly(NativeClientEffectResumeClaim)
  Busy
}

///|
pub(all) enum NativeClientEffectResumeFence {
  Current
  SettlementOnly
  Stale
} derive(Eq, @debug.Debug)

///|
/// Readmission precedes the original journal transaction. An intervening Run
/// revision is refused, including cancellation while signatures are checked.
/// Changed bindings acquire the common observation-only settlement fence;
/// they never discard possibly applied rows or authorize another send.
pub fn NativeClientRunJournal::claim_effect_resume(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  crypto : @crypto.Library,
  authentication : @checkpoint.HostAuthentication,
  reviewers : Array[@checkpoint.ReviewerAuthority],
  keys : Array[@effect_resolution.NativeEffectHostAuthority],
  claimant : String,
  lease_ms : Int64,
  binding : @checkpoint.ResumeBinding,
  current : () -> Bool,
  clock : () -> (String, Int64),
) -> Result[NativeClientEffectResumeAction, NativeClientRunJournalIssue] {
  self.claim_effect_resume_with_operations(
    request,
    crypto,
    authentication,
    reviewers,
    keys,
    claimant,
    lease_ms,
    binding,
    current,
    clock,
    None,
  )
}

///|
fn NativeClientRunJournal::claim_effect_resume_with_operations(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  crypto : @crypto.Library,
  authentication : @checkpoint.HostAuthentication,
  reviewers : Array[@checkpoint.ReviewerAuthority],
  keys : Array[@effect_resolution.NativeEffectHostAuthority],
  claimant : String,
  lease_ms : Int64,
  binding : @checkpoint.ResumeBinding,
  current : () -> Bool,
  clock : () -> (String, Int64),
  operations : NativeClientJournalOperationAccess?,
  expected_revision? : Int64? = None,
) -> Result[NativeClientEffectResumeAction, NativeClientRunJournalIssue] {
  if operations is Some(original) &&
    !physical_equal(self.database, original.reads.database) {
    return Err(CustodyLost)
  }
  let reads = operations.map(original => original.reads)

  if !current() {
    return Err(AuthorizationDenied)
  }
  let before = match self.lookup_with_reads(request, true, reads~) {
    Ok(Retained(value)) => value
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  if expected_revision is Some(revision) && before.revision != revision {
    return Err(Checkpoint(StaleRevision))
  }
  guard before.checkpoint is Some(original) &&
    original.verified_wire is Some(wire) &&
    original.resume_intent_id is Some(intent_id) &&
    original.resume_intent is Some(_) &&
    original.state.status == @publication.Resuming else {
    return Err(Checkpoint(NeedsOriginalContinuation))
  }
  let verified = match
    @effect_resolution.admit_native_effect_resolution(
      crypto,
      original.artifact,
      wire,
      authentication,
      reviewers,
      keys,
      current,
      native_checkpoint_limits(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Checkpoint(Signature(issue)))
  }
  let (at, now_ms) = clock()
  if !current() {
    return Err(AuthorizationDenied)
  }
  guard verified.decision == @checkpoint.Approved &&
    verified.resume_intent_id == Some(intent_id) &&
    original.resolution_cid == Some(verified.resolution_cid) &&
    @checkpoint.resumed_approval(wire, native_checkpoint_limits())
    is Ok(approval) &&
    @checkpoint.resumed_approval_current(approval, at) else {
    return Err(Checkpoint(InvalidMaterial))
  }
  self.transaction_with_reads(
    () => {
      let record = match self.retained(request, reads~) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      if record.revision != before.revision {
        return Err(Checkpoint(StaleRevision))
      }
      guard record.checkpoint is Some(checkpoint) &&
        checkpoint.resume_intent is Some(intent) else {
        return Err(Checkpoint(InvalidMaterial))
      }
      // Leave room for the common Owner's strictly increasing generation.
      if intent.generation >= 9223372036854775806L {
        return Err(Checkpoint(Resume(InvalidIntent)))
      }
      let action = match
        @checkpoint.decide_effect_resume_claim(
          intent,
          claimant,
          now_ms,
          lease_ms,
          checkpoint.binding,
          binding,
          checkpoint.settlement_only || record.cancellation_requested(),
        ) {
        Ok(action) => action
        Err(issue) => return Err(Checkpoint(Resume(issue)))
      }
      let (generation, expires, settlement_only) = match action {
        ClaimIntent(generation, expires) => (generation, expires, false)
        ClaimSettlement(generation, expires) => (generation, expires, true)
        ClaimBusy => return Ok(Busy)
        _ => return Err(Checkpoint(InvalidMaterial))
      }
      let next : @checkpoint.ResumeIntentView = {
        state: ResumeClaimed,
        generation,
        claimant,
        lease_expires_ms: expires,
      }
      match
        self.save_with_operations(
          {
            ..record,
            checkpoint: Some({
              ..checkpoint,
              resume_intent: Some(next),
              settlement_only,
            }),
          },
          operations~,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let claim = {
        journal: self,
        request,
        checkpoint_cid: checkpoint.artifact.checkpoint_cid,
        resolution_cid: verified.resolution_cid,
        intent_id,
        claim: { claimant, generation, },
        original_lease_expires_ms: expires,
        approval,
      }
      Ok(if settlement_only { SettlementOnly(claim) } else { Claimed(claim) })
    },
    reads~,
  )
}

///|
fn NativeClientRunJournal::effect_resume_fence_locked(
  self : NativeClientRunJournal,
  claim : NativeClientEffectResumeClaim,
  now_ms : Int64,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[NativeClientEffectResumeFence, NativeClientRunJournalIssue] {
  if now_ms < 0L || now_ms > 9007199254740991L {
    return Err(Checkpoint(Resume(InvalidClock)))
  }
  if !physical_equal(self, claim.journal) {
    return Ok(Stale)
  }
  let record = match self.retained(claim.request, reads~) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  guard record.checkpoint is Some(checkpoint) &&
    checkpoint.resume_intent is Some(intent) &&
    checkpoint.artifact.checkpoint_cid == claim.checkpoint_cid &&
    checkpoint.resolution_cid == Some(claim.resolution_cid) &&
    checkpoint.resume_intent_id == Some(claim.intent_id) &&
    checkpoint.state.status == @publication.Resuming else {
    return Ok(Stale)
  }
  if @checkpoint.decide_resume_fence(intent, claim.claim, now_ms) !=
    @checkpoint.FenceCurrent {
    return Ok(Stale)
  }
  Ok(
    if checkpoint.settlement_only || record.cancellation_requested() {
      SettlementOnly
    } else {
      Current
    },
  )
}

///|
/// A diagnostic observation, not a send permit: the caller must not cache a
/// successful result across an await or use it instead of a transactional row
/// claim. Cancellation keeps observation/cleanup responsibility but fences send.
pub fn NativeClientRunJournal::effect_resume_fence(
  self : NativeClientRunJournal,
  claim : NativeClientEffectResumeClaim,
  current : () -> Bool,
  clock : () -> Int64,
) -> Result[NativeClientEffectResumeFence, NativeClientRunJournalIssue] {
  self.effect_resume_fence_with_operations(claim, current, clock, None)
}

///|
fn NativeClientRunJournal::effect_resume_fence_with_operations(
  self : NativeClientRunJournal,
  claim : NativeClientEffectResumeClaim,
  current : () -> Bool,
  clock : () -> Int64,
  operations : NativeClientJournalOperationAccess?,
) -> Result[NativeClientEffectResumeFence, NativeClientRunJournalIssue] {
  if operations is Some(original) &&
    !physical_equal(self.database, original.reads.database) {
    return Err(CustodyLost)
  }
  let reads = operations.map(original => original.reads)

  if !current() {
    return Err(AuthorizationDenied)
  }
  let at = clock()
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.transaction_with_reads(
    () => self.effect_resume_fence_locked(claim, at, reads~),
    reads~,
  )
}
