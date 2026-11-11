///|
fn checkpoint_resume_body(
  intent : @checkpoint.ResumeIntentView,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(4096, 16, 2)
  @encode.begin_object(writer)
  for
    (key, value) in [
      ("claimant", intent.claimant),
      ("generation", intent.generation.to_string()),
      ("lease_expires_ms", intent.lease_expires_ms.to_string()),
      (
        "state",
        match intent.state {
          ResumePending => "pending"
          ResumeClaimed => "claimed"
          ResumeCompleted => "completed"
        },
      ),
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, value)
  }
  @encode.end_object(writer)
  @encode.finish(writer)
}

///|
fn read_checkpoint_resume(
  wire : String,
  binding : @checkpoint.ResumeBinding,
) -> @checkpoint.ResumeIntentView? {
  guard checkpoint_cursor(wire) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "claimant", "generation", "lease_expires_ms", "state",
    ])
    is Ok(object) &&
    epoch_text(object, "claimant") is Some(claimant) &&
    epoch_text(object, "generation") is Some(generation_text) &&
    epoch_text(object, "lease_expires_ms") is Some(expires_text) &&
    epoch_text(object, "state") is Some(state_text) else {
    return None
  }
  try {
    let generation = @string.parse_int64(generation_text)
    let lease_expires_ms = @string.parse_int64(expires_text)
    if generation.to_string() != generation_text ||
      lease_expires_ms.to_string() != expires_text {
      return None
    }
    let state = match state_text {
      "pending" if generation == 0L && claimant == "" && lease_expires_ms == 0L =>
        @checkpoint.ResumePending
      "claimed" if generation > 0L &&
        generation < 9223372036854775807L &&
        lease_expires_ms > 0L &&
        lease_expires_ms <= 9007199254740991L => {
        // Use the common Owner and the original retained binding for
        // claimant validation, without granting another claim on restore.
        if @checkpoint.decide_resume_claim(
            {
              state: ResumePending,
              generation: 0L,
              claimant: "",
              lease_expires_ms: 0L,
            },
            claimant,
            0L,
            1L,
            binding,
            binding,
          )
          is Err(_) {
          return None
        }
        @checkpoint.ResumeClaimed
      }
      // Completion needs actual Effect Set/publication facts and is not
      // admitted by this physical claim connection.
      _ => return None
    }
    let view : @checkpoint.ResumeIntentView = {
      state,
      generation,
      claimant,
      lease_expires_ms,
    }
    if checkpoint_resume_body(view) != wire {
      return None
    }
    Some(view)
  } catch {
    _ => None
  }
}

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
  if !current() {
    return Err(AuthorizationDenied)
  }
  let before = match self.lookup(request, true) {
    Ok(Retained(value)) => value
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
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
  self.transaction(() => {
    let record = match self.retained(request) {
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
        checkpoint.settlement_only || record.cancellation_requested,
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
      self.save({
        ..record,
        checkpoint: Some({
          ..checkpoint,
          resume_intent: Some(next),
          settlement_only,
        }),
      }) {
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
      approval,
    }
    Ok(if settlement_only { SettlementOnly(claim) } else { Claimed(claim) })
  })
}

///|
fn NativeClientRunJournal::effect_resume_fence_locked(
  self : NativeClientRunJournal,
  claim : NativeClientEffectResumeClaim,
  now_ms : Int64,
) -> Result[NativeClientEffectResumeFence, NativeClientRunJournalIssue] {
  if now_ms < 0L || now_ms > 9007199254740991L {
    return Err(Checkpoint(Resume(InvalidClock)))
  }
  if !physical_equal(self, claim.journal) {
    return Ok(Stale)
  }
  let record = match self.retained(claim.request) {
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
    if checkpoint.settlement_only || record.cancellation_requested {
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
  if !current() {
    return Err(AuthorizationDenied)
  }
  let at = clock()
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.transaction(() => self.effect_resume_fence_locked(claim, at))
}
