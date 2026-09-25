///|
/// Public Run state transition table of the Execution specification.
pub fn run_transition_allowed(
  from : @publication.RunOutcomeStatus,
  to : @publication.RunOutcomeStatus,
) -> Bool {
  match (from, to) {
    (Preparing, Running) => true
    (Preparing | Running | Resuming, WaitingCheckpoint) => true
    (WaitingCheckpoint, Resuming) => true
    (WaitingCheckpoint, Cancelled) => true
    (Preparing | Resuming, Cancelled) => true
    (Preparing | Running | Resuming, Succeeded | Failed | NeedsReconciliation) =>
      true
    (NeedsReconciliation, NeedsReconciliation | Succeeded | Failed) => true
    _ => false
  }
}

///|
pub fn run_status_token(status : @publication.RunOutcomeStatus) -> String {
  match status {
    Preparing => "preparing"
    Running => "running"
    WaitingCheckpoint => "waiting_checkpoint"
    Resuming => "resuming"
    NeedsReconciliation => "needs_reconciliation"
    Succeeded => "succeeded"
    Failed => "failed"
    Cancelled => "cancelled"
  }
}

///|
pub fn parse_run_status(token : String) -> @publication.RunOutcomeStatus? {
  match token {
    "preparing" => Some(Preparing)
    "running" => Some(Running)
    "waiting_checkpoint" => Some(WaitingCheckpoint)
    "resuming" => Some(Resuming)
    "needs_reconciliation" => Some(NeedsReconciliation)
    "succeeded" => Some(Succeeded)
    "failed" => Some(Failed)
    "cancelled" => Some(Cancelled)
    _ => None
  }
}

///|
/// Decide one Resolution against the Checkpoint closure read in the same
/// store transaction. Dedupe identity is the Resolution CID, which binds the
/// Checkpoint CID: identical redelivery is idempotent, any other Resolution
/// for a closed Checkpoint is a conflict, and an open Checkpoint whose
/// expiration has been reached cannot be resolved.
pub fn decide_resolution_commit(
  checkpoint : SealedCheckpoint,
  closure : CheckpointClosure,
  incoming : VerifiedResolution,
) -> ResolutionCommitAction {
  if incoming.checkpoint_cid != checkpoint.checkpoint_cid {
    return ConflictingResolution
  }
  match closure {
    Resolved(existing) =>
      if existing == incoming.resolution_cid {
        DuplicateResolution
      } else {
        ConflictingResolution
      }
    Expired => CheckpointExpired
    Open =>
      if incoming.verified_at >= checkpoint.checkpoint.expires_at {
        CheckpointExpired
      } else {
        CommitResolution
      }
  }
}

///|
/// Run status entered by committing a verified Resolution.
pub fn resolution_run_status(
  decision : ResolutionDecision,
) -> @publication.RunOutcomeStatus {
  match decision {
    Approved => Resuming
    Rejected => Cancelled
  }
}

///|
fn valid_binding(binding : ResumeBinding) -> Bool {
  valid_cid(binding.authorization_context_cid) &&
  valid_cid(binding.environment_binding_cid)
}

///|
/// Claim a resume intent with a strictly higher fencing generation. A claim
/// is refused while another claimant holds an unexpired lease. If the bound
/// authorization context or environment binding changed while waiting, the
/// intent is completed with `resuming -> failed` and nothing is dispatched.
pub fn decide_resume_claim(
  intent : ResumeIntentView,
  claimant : String,
  now_ms : Int64,
  lease_ms : Int64,
  bound : ResumeBinding,
  current : ResumeBinding,
) -> Result[ResumeClaimAction, ResumeIssue] {
  if !canonical_text(claimant) {
    return Err(InvalidClaimant)
  }
  if lease_ms <= 0L || lease_ms > 86_400_000L {
    return Err(InvalidLease)
  }
  if now_ms < 0L || now_ms > 9_007_199_254_740_991L - lease_ms {
    return Err(InvalidClock)
  }
  if !valid_binding(bound) || !valid_binding(current) {
    return Err(InvalidBinding)
  }
  if intent.generation < 0L {
    return Err(InvalidIntent)
  }
  match intent.state {
    ResumeCompleted => return Ok(ClaimCompleted)
    ResumeClaimed =>
      if now_ms < intent.lease_expires_ms {
        return Ok(ClaimBusy)
      }
    ResumePending => ()
  }
  let generation = intent.generation + 1L
  if bound != current {
    return Ok(ClaimInvalidated(generation))
  }
  Ok(ClaimIntent(generation, now_ms + lease_ms))
}

///|
/// Fence one mutation of a resume intent or its Run. Only the current
/// claimant, holding the current generation and an unexpired lease, may renew
/// or complete. Everything else is stale and must not change durable state.
pub fn decide_resume_fence(
  intent : ResumeIntentView,
  claim : ResumeClaim,
  now_ms : Int64,
) -> ResumeFenceAction {
  if intent.state == ResumeClaimed &&
    intent.generation == claim.generation &&
    intent.claimant == claim.claimant &&
    now_ms < intent.lease_expires_ms {
    FenceCurrent
  } else {
    FenceStale
  }
}

///|
/// Destinations a resumed Run may reach when its resume intent completes.
/// The transition table has no `resuming -> running`; progress of the
/// resumed continuation stays `resuming` until one of these is committed.
pub fn resume_completion_allowed(to : @publication.RunOutcomeStatus) -> Bool {
  to != Resuming && run_transition_allowed(Resuming, to)
}
