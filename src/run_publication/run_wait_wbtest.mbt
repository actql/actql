///|
fn wait_fixture(status : String, revision : String) -> String {
  let action = match status {
    "waiting_checkpoint" =>
      "\"checkpoint\":{\"checkpoint_id\":\"original-checkpoint\",\"checkpoint_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"kind\":\"run_scope\"},\"next_action\":{\"kind\":\"resolve_checkpoint\",\"checkpoint_id\":\"original-checkpoint\"}"
    "needs_reconciliation" =>
      "\"next_action\":{\"kind\":\"reconcile_run\",\"reason\":\"execution_unknown\"}"
    _ => "\"next_action\":{\"kind\":\"none\"}"
  }
  "{\"version\":\"actql-run-state/0.1\",\"run_id\":\"original-run\",\"status\":\"" +
  status +
  "\",\"revision\":" +
  revision +
  ",\"updated_at\":\"2026-10-16T00:00:00.000Z\",\"result_available\":false,\"result_availability\":{}," +
  action +
  "}"
}

///|
test "Run wait accepts only stable original observations above since" {
  for
    status in [
      "waiting_checkpoint", "needs_reconciliation", "succeeded", "failed", "cancelled",
    ] {
    let wire = wait_fixture(status, "7")
    assert_eq(run_wait_ready(wire, None, 65536, 1024, 16), Ok(true))
    assert_eq(run_wait_ready(wire, Some(6L), 65536, 1024, 16), Ok(true))
    assert_eq(run_wait_ready(wire, Some(7L), 65536, 1024, 16), Ok(false))
    assert_eq(
      run_wait_ready(wire, Some(8L), 65536, 1024, 16),
      Err(InvalidSince),
    )
  }
  for status in ["preparing", "running", "resuming"] {
    let wire = wait_fixture(status, "7")
    assert_eq(run_wait_ready(wire, None, 65536, 1024, 16), Ok(false))
    assert_eq(run_wait_ready(wire, Some(6L), 65536, 1024, 16), Ok(false))
  }
}

///|
test "Run wait rejects invalid revisions without repairing missing current state" {
  let wire = wait_fixture("succeeded", "0")
  assert_eq(run_wait_ready(wire, None, 65536, 1024, 16), Ok(true))
  assert_eq(run_wait_ready(wire, Some(0L), 65536, 1024, 16), Ok(false))
  for bad in [-1L, 9007199254740992L] {
    assert_eq(
      run_wait_ready(wire, Some(bad), 65536, 1024, 16),
      Err(InvalidSince),
    )
  }
  for bad in ["null", "true", "\"7\"", "-1", "1.5", "9007199254740992"] {
    assert_eq(
      run_wait_ready(wait_fixture("succeeded", bad), None, 65536, 1024, 16),
      Err(InvalidState),
    )
  }
  assert_eq(
    run_wait_ready(
      wire.replace(old="\"revision\":0,", new=""),
      None,
      65536,
      1024,
      16,
    ),
    Err(InvalidState),
  )
  assert_eq(
    run_wait_ready(wait_fixture("invented", "7"), None, 65536, 1024, 16),
    Err(InvalidState),
  )
  assert_eq(
    run_wait_ready(
      wait_fixture("succeeded", "9007199254740991"),
      Some(9007199254740990L),
      65536,
      1024,
      16,
    ),
    Ok(true),
  )
}
