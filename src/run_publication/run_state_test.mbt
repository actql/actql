///|
fn observation(
  name : String,
  state : ResultAvailabilityState,
  reason : ResultAvailabilityReason,
) -> ResultAvailability {
  { name, state, reason, }
}

///|
test "succeeded Run admits only availability actions or no action" {
  let available = [observation("answer", Available, ConfirmedPresent)]
  assert_true(
    validate_run_state(
      Succeeded,
      ["answer"],
      available,
      true,
      ReadResult(["answer"]),
      false,
    )
    is Ok(_),
  )
  assert_true(
    validate_run_state(
      Succeeded,
      ["answer"],
      available,
      true,
      ResolveCheckpoint,
      false,
    )
    is Err(ActionStatusMismatch),
  )
  assert_true(
    validate_run_state(Succeeded, ["answer"], available, true, Reconcile, false)
    is Err(ActionStatusMismatch),
  )
}

///|
test "succeeded Run remains terminal when Results are unavailable or unknown" {
  assert_true(
    validate_run_state(
      Succeeded,
      ["answer"],
      [observation("answer", Unavailable, Deleted)],
      false,
      NoAction,
      false,
    )
    is Ok(_),
  )
  assert_true(
    validate_run_state(
      Succeeded,
      ["answer"],
      [observation("answer", Unknown, StoreQueryFailed)],
      false,
      RefreshAvailability(["answer"]),
      false,
    )
    is Ok(_),
  )
}

///|
test "read and refresh actions bind exact eligible Result names" {
  let states = [
    observation("ready", Available, ConfirmedPresent),
    observation("gone", Unavailable, RetentionExpired),
    observation("uncertain", Unknown, VerificationPending),
  ]
  let declared = ["ready", "gone", "uncertain"]
  assert_true(
    validate_run_state(
      Succeeded,
      declared,
      states,
      false,
      ReadResult(["gone"]),
      false,
    )
    is Err(ResultNotAvailable("gone")),
  )
  assert_true(
    validate_run_state(
      Succeeded,
      declared,
      states,
      false,
      ReadResult(["missing"]),
      false,
    )
    is Err(UnknownActionResult("missing")),
  )
  assert_true(
    validate_run_state(
      Succeeded,
      declared,
      states,
      false,
      RefreshAvailability(["ready"]),
      false,
    )
    is Err(ResultNotUnknown("ready")),
  )
  assert_true(
    validate_run_state(
      Succeeded,
      declared,
      states,
      false,
      ReadResult(["ready"]),
      false,
    )
    is Ok(_),
  )
}

///|
test "aggregate and inventory cover every declared Result exactly" {
  let partial = [
    observation("first", Available, ConfirmedPresent),
    observation("second", Unavailable, PolicyUnavailable),
  ]
  assert_true(
    validate_run_state(
      Succeeded,
      ["first", "second"],
      partial,
      true,
      NoAction,
      false,
    )
    is Err(AggregateMismatch),
  )
  assert_true(
    validate_run_state(
      Succeeded,
      ["first", "second"],
      [partial[0]],
      false,
      NoAction,
      false,
    )
    is Err(MissingAvailability("second")),
  )
  assert_true(
    validate_run_state(
      Succeeded,
      ["first"],
      [partial[0], partial[1]],
      false,
      NoAction,
      false,
    )
    is Err(ForeignAvailability("second")),
  )
  assert_true(
    validate_run_state(
      Succeeded,
      ["first", "second"],
      partial,
      false,
      ReadResult(["first"]),
      false,
    )
    is Ok(_),
  )
}

///|
test "checkpoint and reconciliation constraints remain disjoint" {
  let unavailable = [observation("answer", Unavailable, NotPublished)]
  assert_true(
    validate_run_state(
      WaitingCheckpoint,
      ["answer"],
      unavailable,
      false,
      ResolveCheckpoint,
      true,
    )
    is Ok(_),
  )
  assert_true(
    validate_run_state(
      WaitingCheckpoint,
      ["answer"],
      unavailable,
      false,
      NoAction,
      true,
    )
    is Err(ActionStatusMismatch),
  )
  assert_true(
    validate_run_state(
      NeedsReconciliation,
      ["answer"],
      unavailable,
      false,
      Reconcile,
      false,
    )
    is Ok(_),
  )
  assert_true(
    validate_run_state(
      Running,
      ["answer"],
      unavailable,
      false,
      ResolveCheckpoint,
      false,
    )
    is Err(ActionStatusMismatch),
  )
}

///|
test "succeeded Run state wire derives aggregate and action in MoonBit" {
  let observations = [
    observation("uncertain", Unknown, StoreQueryFailed),
    observation("ready", Available, ConfirmedPresent),
    observation("gone", Unavailable, RetentionExpired),
  ]
  let wire = issue_succeeded_run_state(
    "run-a",
    "2026-09-18T04:00:00.000Z",
    ["ready", "gone", "uncertain"],
    observations,
    [
      "2026-09-18T03:00:02.000Z", "2026-09-18T03:00:00.000Z", "2026-09-18T03:00:01.000Z",
    ],
    16384,
    256,
    8,
  )
  assert_eq(
    wire,
    Ok(
      "{\"next_action\":{\"kind\":\"refresh_availability\"," +
      "\"results\":[\"uncertain\"]},\"result_availability\":{" +
      "\"gone\":{\"observed_at\":\"2026-09-18T03:00:01.000Z\"," +
      "\"reason\":\"retention_expired\",\"state\":\"unavailable\"}," +
      "\"ready\":{\"observed_at\":\"2026-09-18T03:00:00.000Z\"," +
      "\"reason\":\"confirmed_present\",\"state\":\"available\"}," +
      "\"uncertain\":{\"observed_at\":\"2026-09-18T03:00:02.000Z\"," +
      "\"reason\":\"store_query_failed\",\"state\":\"unknown\"}}," +
      "\"result_available\":false,\"run_id\":\"run-a\"," +
      "\"status\":\"succeeded\"," +
      "\"updated_at\":\"2026-09-18T04:00:00.000Z\"," +
      "\"version\":\"actql-run-state/0.1\"}",
    ),
  )
}

///|
test "succeeded Run state offers only confirmed available Results" {
  let wire = issue_succeeded_run_state(
    "run-a",
    "2026-09-18T04:00:00.000Z",
    ["second", "first"],
    [
      observation("second", Unavailable, Deleted),
      observation("first", Available, ConfirmedPresent),
    ],
    ["2026-09-18T03:00:01.000Z", "2026-09-18T03:00:00.000Z"],
    16384,
    256,
    8,
  )
  assert_true(wire is Ok(value) && value.contains("\"results\":[\"first\"]"))
  assert_true(
    issue_succeeded_run_state(
      "run-a",
      "invalid",
      ["first"],
      [observation("first", Available, ConfirmedPresent)],
      ["2026-09-18T03:00:00.000Z"],
      16384,
      256,
      8,
    )
    is Err(InvalidObservationTime("run")),
  )
}
