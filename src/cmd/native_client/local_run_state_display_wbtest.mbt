///|
let run_display_minimal : String =
  #|{"version":"actql-run-state/0.1","run_id":"original-run","status":"running","revision":7,"updated_at":"2026-10-17T00:00:00.000Z","next_action":{"kind":"none"},"result_available":false,"result_availability":{}}

///|
let run_display_minimal_expected : String = "Run: \"original-run\"\nState: \"running\"\nState revision: 7\nUpdated: \"2026-10-17T00:00:00.000Z\"\nNext action: \"none\"\nResult available: false\nResult observations: none\n"

///|
test "human State keeps succeeded separate from unknown Result and physical stop" {
  let original =
    #|{"version":"actql-run-state/0.1","run_id":"original-run","status":"succeeded","revision":53,"updated_at":"2026-10-17T00:00:00.000Z","next_action":{"kind":"refresh_availability","results":["answer"]},"result_available":false,"result_availability":{"answer":{"state":"unknown","observed_at":"2026-10-17T00:00:00.000Z","reason":"verification_pending"}},"control":{"revision":2,"cancellation_requested":false,"physical_stop":"unknown"}}
  let expected = "Run: \"original-run\"\nState: \"succeeded\"\nState revision: 53\nUpdated: \"2026-10-17T00:00:00.000Z\"\nNext action: \"refresh_availability\"\n  results: \"answer\"\nResult available: false\nResult \"answer\": \"unknown\"\n  Reason: \"verification_pending\"\n  Observed: \"2026-10-17T00:00:00.000Z\"\nControl revision: 2\nCancellation requested: false\nPhysical stop: \"unknown\"\n"
  assert_eq(local_run_state_display(original), Some(expected))
}

///|
test "human State displays the original Checkpoint without an approval claim" {
  let original =
    #|{"version":"actql-run-state/0.1","run_id":"paused-run","status":"waiting_checkpoint","revision":3,"updated_at":"2026-10-17T00:00:00.000Z","checkpoint":{"checkpoint_id":"original-checkpoint","checkpoint_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","kind":"effect_set"},"next_action":{"kind":"resolve_checkpoint","checkpoint_id":"original-checkpoint"},"result_available":false,"result_availability":{}}
  let human = local_run_state_display(original).unwrap()
  assert_true(human.contains("State: \"waiting_checkpoint\"\n"))
  assert_true(
    human.contains(
      "Checkpoint: \"original-checkpoint\"\n  Kind: \"effect_set\"\n",
    ),
  )
  assert_true(
    human.contains(
      "Original CID: \"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"",
    ),
  )
  assert_true(
    human.contains(
      "Next action: \"resolve_checkpoint\"\n  checkpoint_id: \"original-checkpoint\"\n",
    ),
  )
  assert_false(human.contains("approved"))
}

///|
test "human State preserves Run and Effect reconciliation as different facts" {
  let run_unknown =
    #|{"version":"actql-run-state/0.1","run_id":"unknown-run","status":"needs_reconciliation","revision":4,"updated_at":"2026-10-17T00:00:00.000Z","next_action":{"kind":"reconcile_run","reason":"execution_unknown"},"result_available":false,"result_availability":{}}
  let effect_unknown =
    #|{"version":"actql-run-state/0.1","run_id":"unknown-effect","status":"needs_reconciliation","revision":5,"updated_at":"2026-10-17T00:00:00.000Z","next_action":{"kind":"reconcile","effects":["original-effect"]},"result_available":false,"result_availability":{}}
  assert_true(
    local_run_state_display(run_unknown)
    .unwrap()
    .contains(
      "Next action: \"reconcile_run\"\n  reason: \"execution_unknown\"\n",
    ),
  )
  assert_true(
    local_run_state_display(effect_unknown)
    .unwrap()
    .contains("Next action: \"reconcile\"\n  effects: \"original-effect\"\n"),
  )
}

///|
test "human State copies original progress and terminal status without promotion" {
  for status in ["preparing", "running", "resuming", "succeeded", "cancelled"] {
    let original = "{\"version\":\"actql-run-state/0.1\",\"run_id\":\"original\",\"status\":\"" +
      status +
      "\",\"revision\":7,\"updated_at\":\"2026-10-17T00:00:00.000Z\",\"next_action\":{\"kind\":\"none\"},\"result_available\":false,\"result_availability\":{}}"
    let human = local_run_state_display(original).unwrap()
    assert_true(human.contains("State: \"" + status + "\"\n"))
    assert_true(
      human.contains("Result available: false\nResult observations: none\n"),
    )
    assert_false(human.contains("Control revision:"))
    assert_false(human.contains("Physical stop:"))
  }
}

///|
test "human State quotes original names and diagnostic terminal controls" {
  let original =
    #|{"version":"actql-run-state/0.1","run_id":"run\n\u001b[31m","status":"failed","revision":1,"updated_at":"2026-10-17T00:00:00.000Z","next_action":{"kind":"none"},"result_available":false,"result_availability":{},"terminal_error":{"code":"ACTQL_E_ORIGINAL","message":"not acknowledged\n\u001b[0m"}}
  let human = local_run_state_display(original).unwrap()
  assert_true(human.has_prefix("Run: \"run\\n\\u001b[31m\"\n"))
  assert_true(human.contains("Error: \"ACTQL_E_ORIGINAL\"\n"))
  assert_true(human.contains("Message: \"not acknowledged\\n\\u001b[0m\"\n"))
  assert_false(human.contains("\u{001b}"))
}

///|
test "human State exact output bound succeeds and one byte short refuses" {
  let limit = @utf8.encode(run_display_minimal_expected).length()
  assert_eq(
    local_run_state_display(run_display_minimal, maximum=limit),
    Some(run_display_minimal_expected),
  )
  assert_eq(
    local_run_state_display(run_display_minimal, maximum=limit - 1),
    None,
  )
  assert_eq(local_run_state_display(run_display_minimal, maximum=65537), None)
  assert_eq(local_run_state_display(run_display_minimal, maximum=-1), None)
}

///|
test "human State does not turn incomplete legacy or oversize replies into State" {
  for
    original in [
      "SubmissionUnknown original-reference original-attempt",
      "{",
      "{}",
      "{\"version\":\"not-a-state\"}",
      "{\"version\":\"actql-run-state/0.1\",\"run_id\":\"missing-state\"}",
      "{\"version\":\"actql-run-state/0.1\",\"run_id\":\"" +
      "x".repeat(65537) +
      "\"}",
    ] {
    assert_eq(local_run_state_display(original), None)
  }
}

///|
test "human State independently displays expired unavailable and confirmed available Results" {
  let original =
    #|{"version":"actql-run-state/0.1","run_id":"original-run","status":"succeeded","revision":9,"updated_at":"2026-10-17T00:00:00.000Z","next_action":{"kind":"read_result","results":["current"]},"result_available":true,"result_availability":{"expired":{"state":"unavailable","reason":"retention_expired","observed_at":"2026-10-17T00:00:00.000Z"},"current":{"state":"available","reason":"confirmed_present","observed_at":"2026-10-17T00:00:00.000Z"}}}
  let human = local_run_state_display(original).unwrap()
  assert_true(human.contains("Result available: true\n"))
  assert_true(
    human.contains(
      "Result \"expired\": \"unavailable\"\n  Reason: \"retention_expired\"\n",
    ),
  )
  assert_true(
    human.contains(
      "Result \"current\": \"available\"\n  Reason: \"confirmed_present\"\n",
    ),
  )
}

///|
test "human and JSON run replies retain original response bytes independently" {
  let json = run_command_fixture(true).subcommand.unwrap().1
  let human = run_command_fixture(false).subcommand.unwrap().1
  assert_eq(local_run_reply(json, run_display_minimal), run_display_minimal)
  assert_eq(
    local_run_reply(human, run_display_minimal),
    run_display_minimal_expected,
  )
  let unknown = "SubmissionUnknown original-reference original-attempt"
  assert_eq(local_run_reply(json, unknown), unknown)
  assert_eq(
    local_run_reply(human, unknown),
    "Local run response (original Submission preserved):\n" + unknown,
  )
}
