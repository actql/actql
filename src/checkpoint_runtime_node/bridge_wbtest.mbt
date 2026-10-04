///|
test "checkpoint ABI exposes stable issue codes separately from diagnostics" {
  let checkpoint = parse(fail_checkpoint(MissingField("checkpoint_id"))).unwrap()
  assert_eq(text_member(checkpoint, "issue"), Some("MissingField"))
  assert_eq(
    text_member(checkpoint, "detail"),
    Some("MissingField(\"checkpoint_id\")"),
  )
  let resolution = parse(fail_resolution(CheckpointBindingMismatch("run_id"))).unwrap()
  assert_eq(text_member(resolution, "issue"), Some("CheckpointBindingMismatch"))
  assert_eq(
    text_member(resolution, "detail"),
    Some("CheckpointBindingMismatch(\"run_id\")"),
  )
  let state = parse(fail_run_state(RunStateInvalidField("status"))).unwrap()
  assert_eq(text_member(state, "issue"), Some("RunStateInvalidField"))
  assert_eq(
    text_member(state, "detail"),
    Some("RunStateInvalidField(\"status\")"),
  )
  let claim = parse(fail_resume(InvalidClaimant)).unwrap()
  assert_eq(text_member(claim, "issue"), Some("InvalidClaimant"))
  assert_eq(text_member(claim, "detail"), Some("InvalidClaimant"))
  let malformed = parse(checkpoint_admit("{")).unwrap()
  assert_eq(text_member(malformed, "issue"), Some("InvalidWire"))
}

///|
test "terminal outcome bridge rejects unknown and unparseable tokens" {
  assert_eq(run_outcome_terminal("preparing"), false)
  assert_eq(run_outcome_terminal("running"), false)
  assert_eq(run_outcome_terminal("waiting_checkpoint"), false)
  assert_eq(run_outcome_terminal("resuming"), false)
  assert_eq(run_outcome_terminal("needs_reconciliation"), false)
  assert_eq(run_outcome_terminal("succeeded"), true)
  assert_eq(run_outcome_terminal("failed"), true)
  assert_eq(run_outcome_terminal("cancelled"), true)
  assert_eq(run_outcome_terminal("unknown"), false)
  assert_eq(run_outcome_terminal("Succeeded"), false)
  assert_eq(run_outcome_terminal("succeeded "), false)
  assert_eq(run_outcome_terminal(""), false)
  assert_eq(run_outcome_terminal("{\"status\":\"succeeded\"}"), false)
}
