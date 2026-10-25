///|
test "confirmed cancellation DATA uses the existing canonical unpublished Run format" {
  let names = ["z", "a"]
  assert_eq(
    issue_confirmed_cancelled_unpublished_run_state_wire(
      "confirmed-run", "2026-10-25T00:00:00.000Z", names, 8192, 128, 16,
    ),
    Ok(
      "{\"next_action\":{\"kind\":\"none\"}," +
      "\"result_availability\":{\"a\":{\"observed_at\":\"2026-10-25T00:00:00.000Z\",\"reason\":\"not_published\",\"state\":\"unavailable\"}," +
      "\"z\":{\"observed_at\":\"2026-10-25T00:00:00.000Z\",\"reason\":\"not_published\",\"state\":\"unavailable\"}}," +
      "\"result_available\":false,\"run_id\":\"confirmed-run\",\"status\":\"cancelled\"," +
      "\"updated_at\":\"2026-10-25T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"}",
    ),
  )
  assert_eq(names, ["z", "a"])
  assert_eq(
    issue_confirmed_cancelled_unpublished_run_state_wire(
      "confirmed-run",
      "2026-10-25T00:00:00.000Z",
      [],
      8192,
      128,
      16,
    ),
    Ok(
      "{\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false," +
      "\"run_id\":\"confirmed-run\",\"status\":\"cancelled\",\"updated_at\":\"2026-10-25T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"}",
    ),
  )
}

///|
test "confirmed cancellation DATA retains identity inventory and encoding refusals" {
  let at = "2026-10-25T00:00:00.000Z"
  assert_true(
    issue_confirmed_cancelled_unpublished_run_state_wire(
      "",
      "invalid",
      ["a", "a"],
      0,
      0,
      0,
    )
    is Err(InvalidRunId),
  )
  assert_true(
    issue_confirmed_cancelled_unpublished_run_state_wire(
      "run",
      "invalid",
      ["a", "a"],
      0,
      0,
      0,
    )
    is Err(InvalidObservationTime("run")),
  )
  assert_true(
    issue_confirmed_cancelled_unpublished_run_state_wire(
      "run",
      at,
      ["a", "a"],
      0,
      0,
      0,
    )
    is Err(DuplicateDeclaredResult("a")),
  )
  assert_true(
    issue_confirmed_cancelled_unpublished_run_state_wire(
      "run",
      at,
      [""],
      8192,
      128,
      16,
    )
    is Err(InvalidResultName("")),
  )
  assert_true(
    issue_confirmed_cancelled_unpublished_run_state_wire(
      "run",
      at,
      ["e\u0301"],
      8192,
      128,
      16,
    )
    is Err(InvalidResultName("e\u0301")),
  )
  for limits in [(0, 128, 16), (32, 128, 16), (8192, 1, 16), (8192, 128, 1)] {
    assert_true(
      issue_confirmed_cancelled_unpublished_run_state_wire(
        "run",
        at,
        ["a"],
        limits.0,
        limits.1,
        limits.2,
      )
      is Err(Encoding),
    )
  }
}

///|
test "unpublished computation fact validation keeps its original error priority" {
  let at = "2026-10-25T00:00:00.000Z"
  assert_true(
    issue_pre_checkpoint_unpublished_run_state_wire(
      "",
      "invalid",
      ["a", "a"],
      false,
      true,
      0,
      0,
      0,
    )
    is Err(InvalidRunId),
  )
  assert_true(
    issue_pre_checkpoint_unpublished_run_state_wire(
      "run",
      "invalid",
      ["a", "a"],
      false,
      true,
      0,
      0,
      0,
    )
    is Err(InvalidObservationTime("run")),
  )
  assert_true(
    issue_pre_checkpoint_unpublished_run_state_wire(
      "run",
      at,
      ["a", "a"],
      false,
      true,
      0,
      0,
      0,
    )
    is Err(ActionStatusMismatch),
  )
  assert_true(
    issue_pre_checkpoint_unpublished_run_state_wire(
      "run",
      at,
      ["a", "a"],
      true,
      false,
      0,
      0,
      0,
      execution_unknown=true,
      observed_terminal_outcome=Some(Cancelled),
    )
    is Err(ActionStatusMismatch),
  )
  assert_eq(
    issue_pre_checkpoint_unpublished_run_state_wire(
      "run",
      at,
      ["a"],
      true,
      false,
      8192,
      128,
      16,
      observed_terminal_outcome=Some(Cancelled),
    ),
    issue_confirmed_cancelled_unpublished_run_state_wire(
      "run",
      at,
      ["a"],
      8192,
      128,
      16,
    ),
  )
}
