///|
fn failed_state_test_outcomes(state : String) -> EffectSetApplyReceiptEvidence {
  let preview = effect_receipt_test_preview()
  let receipt = partition_test_member(preview, 0, state)
  let set = issue_effect_set_apply_receipt_from_members(
    preview,
    [receipt],
    [false],
    16384,
    512,
    16,
  ).unwrap()
  admit_effect_set_apply_receipt_evidence(
    preview,
    set.wire,
    [receipt.wire],
    16384,
    512,
    16,
  ).unwrap()
}

///|
test "known failed projection uses the entire admitted partition and existing failed writer" {
  for
    state in [
      "failed", "rolled_back", "unattempted", "unknown", "applied", "accepted",
    ] {
    let original = failed_state_test_outcomes(state)
    let result = issue_admitted_effect_failed_run_state_wire(
      original,
      "original-run",
      "2026-09-18T00:00:00.000Z",
      ["answer"],
      16384,
      512,
      16,
    )
    if state == "failed" || state == "rolled_back" || state == "unattempted" {
      assert_eq(
        result.unwrap(),
        "{\"next_action\":{\"kind\":\"none\"}," +
        "\"result_availability\":{\"answer\":{\"observed_at\":\"2026-09-18T00:00:00.000Z\"," +
        "\"reason\":\"not_published\",\"state\":\"unavailable\"}},\"result_available\":false," +
        "\"run_id\":\"original-run\",\"status\":\"failed\"," +
        "\"terminal_error\":{\"code\":\"ACTQL_E_UNPUBLISHED_RUN\",\"message\":\"Run ended before publication\"}," +
        "\"updated_at\":\"2026-09-18T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"}",
      )
      assert_eq(effect_set_apply_receipt_run_status(original), "failed")
    } else {
      assert_true(result is Err(ActionStatusMismatch))
    }
  }
}

///|
test "known failed projection preserves identity declaration and encoding limits" {
  let original = failed_state_test_outcomes("failed")
  assert_true(
    issue_admitted_effect_failed_run_state_wire(
      original,
      "",
      "2026-09-18T00:00:00.000Z",
      ["answer"],
      16384,
      512,
      16,
    )
    is Err(InvalidRunId),
  )
  assert_true(
    issue_admitted_effect_failed_run_state_wire(
      original,
      "original-run",
      "invalid",
      ["answer"],
      16384,
      512,
      16,
    )
    is Err(InvalidObservationTime(_)),
  )
  assert_true(
    issue_admitted_effect_failed_run_state_wire(
      original,
      "original-run",
      "2026-09-18T00:00:00.000Z",
      ["answer", "answer"],
      16384,
      512,
      16,
    )
    is Err(_),
  )
  assert_true(
    issue_admitted_effect_failed_run_state_wire(
      original,
      "original-run",
      "2026-09-18T00:00:00.000Z",
      ["answer"],
      8,
      512,
      16,
    )
    is Err(Encoding),
  )
}
