///|
fn run_observation_fixture(status : String, revision : String) -> String {
  let action = if status == "needs_reconciliation" {
    "{\"kind\":\"reconcile_run\",\"reason\":\"execution_unknown\"}"
  } else {
    "{\"kind\":\"none\"}"
  }
  "{\"version\":\"actql-run-state/0.1\",\"run_id\":\"same-run\",\"status\":\"" +
  status +
  "\"," +
  revision +
  "\"updated_at\":\"2026-10-17T00:00:00.000Z\",\"result_available\":false,\"result_availability\":{},\"next_action\":" +
  action +
  "}"
}

///|
test "Run projection ABI retains original clocks revision and foreign Run rejection" {
  let raw = run_observation_fixture("succeeded", "")
  let first = run_state_observation_prepare(
    raw, "same-run", 0L, 65536, 1024, 16,
  ).unwrap()
  assert_eq(run_state_observation_next_revision(first, false, "", 0L), Ok(0L))
  let wire = run_state_observation_wire(first, 0L).unwrap()
  assert_true(wire.contains("\"revision\":0"))
  let next = run_state_observation_prepare(
    raw.replace(old="00:00:00", new="00:00:01"),
    "same-run",
    0L,
    65536,
    1024,
    16,
  ).unwrap()
  assert_eq(run_state_observation_key(first), run_state_observation_key(next))
  assert_eq(
    run_state_observation_next_revision(
      next,
      true,
      run_state_observation_key(first),
      0L,
    ),
    Ok(0L),
  )
  assert_true(
    run_state_observation_prepare(raw, "foreign-run", 0L, 65536, 1024, 16)
    is Err("ForeignRunStateObservation"),
  )
}

///|
test "Run projection ABI keeps actual change exhaustion and missing prior distinct" {
  let old = run_state_observation_prepare(
    run_observation_fixture("running", ""),
    "same-run",
    4L,
    65536,
    1024,
    16,
  ).unwrap()
  let next = run_state_observation_prepare(
    run_observation_fixture("succeeded", ""),
    "same-run",
    4L,
    65536,
    1024,
    16,
  ).unwrap()
  assert_eq(
    run_state_observation_next_revision(
      next,
      true,
      run_state_observation_key(old),
      4L,
    ),
    Ok(5L),
  )
  assert_eq(
    run_state_observation_next_revision(next, false, "", 4L),
    Err("InvalidPriorRunStateObservation"),
  )
  assert_eq(
    run_state_observation_next_revision(
      next,
      true,
      run_state_observation_key(old),
      9007199254740991L,
    ),
    Err("RunStateRevisionExhausted"),
  )
  assert_eq(
    run_state_observation_wire(next, -1L),
    Err("InvalidRunStateRevision"),
  )
}

///|
test "Run wait ABI uses original stable since and typed refusal without a clock" {
  let wire = run_observation_fixture("needs_reconciliation", "\"revision\":7,")
  assert_eq(run_state_wait_decision(wire, false, 0L, 65536, 1024, 16), "ready")
  assert_eq(run_state_wait_decision(wire, true, 6L, 65536, 1024, 16), "ready")
  assert_eq(run_state_wait_decision(wire, true, 7L, 65536, 1024, 16), "pending")
  assert_eq(
    run_state_wait_decision(wire, true, 8L, 65536, 1024, 16),
    "InvalidWaitRevision",
  )
  assert_eq(
    run_state_wait_decision(
      run_observation_fixture("running", "\"revision\":7,"),
      true,
      6L,
      65536,
      1024,
      16,
    ),
    "pending",
  )
  assert_eq(
    run_state_wait_decision(
      run_observation_fixture("succeeded", ""),
      false,
      0L,
      65536,
      1024,
      16,
    ),
    "InvalidRunWaitState",
  )
  assert_eq(
    run_state_wait_decision(wire, false, 0L, 1, 1024, 16),
    "InvalidRunWaitState",
  )
}
