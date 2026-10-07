///|
test "Effect settlement retains a fence without granting another execution" {
  let original : ResumeBinding = {
    authorization_context_cid: "sha256:" + "a".repeat(64),
    environment_binding_cid: "sha256:" + "b".repeat(64),
  }
  let changed = {
    ..original,
    environment_binding_cid: "sha256:" + "c".repeat(64),
  }
  let pending : ResumeIntentView = {
    state: ResumePending,
    generation: 0L,
    claimant: "",
    lease_expires_ms: 0L,
  }
  assert_eq(
    decide_effect_resume_claim(
      pending, "observer", 1000L, 500L, original, changed, false,
    ),
    Ok(ClaimSettlement(1L, 1500L)),
  )
  assert_eq(
    decide_resume_claim(pending, "executor", 1000L, 500L, original, changed),
    Ok(ClaimInvalidated(1L)),
  )
  assert_eq(
    decide_effect_resume_claim(
      pending, "executor", 1000L, 500L, original, original, false,
    ),
    Ok(ClaimIntent(1L, 1500L)),
  )
  let held : ResumeIntentView = {
    state: ResumeClaimed,
    generation: 1L,
    claimant: "observer",
    lease_expires_ms: 1500L,
  }
  assert_eq(
    decide_effect_resume_claim(
      held, "next", 1499L, 500L, original, original, true,
    ),
    Ok(ClaimBusy),
  )
  assert_eq(
    decide_effect_resume_claim(
      held, "next", 1500L, 500L, original, original, true,
    ),
    Ok(ClaimSettlement(2L, 2000L)),
  )
  assert_eq(
    decide_effect_resume_claim(
      { ..held, state: ResumeCompleted, },
      "next",
      9000L,
      500L,
      original,
      changed,
      true,
    ),
    Ok(ClaimCompleted),
  )
}

///|
test "Effect settlement cannot relax the ordinary claim validation" {
  let bound : ResumeBinding = {
    authorization_context_cid: "sha256:" + "a".repeat(64),
    environment_binding_cid: "sha256:" + "b".repeat(64),
  }
  let intent : ResumeIntentView = {
    state: ResumePending,
    generation: 0L,
    claimant: "",
    lease_expires_ms: 0L,
  }
  assert_eq(
    decide_effect_resume_claim(intent, "", 0L, 1L, bound, bound, true),
    Err(InvalidClaimant),
  )
  assert_eq(
    decide_effect_resume_claim(intent, "o", 0L, 0L, bound, bound, true),
    Err(InvalidLease),
  )
  assert_eq(
    decide_effect_resume_claim(intent, "o", -1L, 1L, bound, bound, true),
    Err(InvalidClock),
  )
  assert_eq(
    decide_effect_resume_claim(
      intent, "o", 9007199254740991L, 1L, bound, bound, true,
    ),
    Err(InvalidClock),
  )
  assert_eq(
    decide_effect_resume_claim(
      { ..intent, generation: -1L, },
      "o",
      0L,
      1L,
      bound,
      bound,
      true,
    ),
    Err(InvalidIntent),
  )
}

///|
test "Effect settlement cannot open execution or erase unknown work as cancellation" {
  for status in [
    @publication.RunOutcomeStatus::Failed,
    @publication.RunOutcomeStatus::NeedsReconciliation,
  ] {
    assert_true(effect_settlement_completion_allowed(status))
  }
  for status in [
    @publication.RunOutcomeStatus::Preparing,
    @publication.RunOutcomeStatus::Running,
    @publication.RunOutcomeStatus::WaitingCheckpoint,
    @publication.RunOutcomeStatus::Resuming,
    @publication.RunOutcomeStatus::Succeeded,
    @publication.RunOutcomeStatus::Cancelled,
  ] {
    assert_false(effect_settlement_completion_allowed(status))
  }
}
