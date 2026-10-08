///|
test "Run observation key preserves each independent Owner fact" {
  assert_eq(
    run_observation_key("running", 7L, None, None),
    Some("running;7;?;?"),
  )
  assert_eq(
    run_observation_key("succeeded", 7L, Some(true), None),
    Some("succeeded;7;1;?"),
  )
  assert_eq(
    run_observation_key("succeeded", 7L, Some(false), Some(true)),
    Some("succeeded;7;0;1"),
  )
  assert_eq(
    run_observation_key("succeeded", 8L, Some(false), Some(true)),
    Some("succeeded;8;0;1"),
  )
  assert_eq(
    run_observation_key("needs_reconciliation", 0L, None, Some(false)),
    Some("needs_reconciliation;0;?;0"),
  )
}

///|
test "Run observation key rejects unknown outcome and inexact revision" {
  assert_eq(run_observation_key("unknown", 0L, None, None), None)
  assert_eq(run_observation_key("Running", 0L, None, None), None)
  assert_eq(run_observation_key("running", -1L, None, None), None)
  assert_eq(run_observation_key("running", 9007199254740992L, None, None), None)
  assert_eq(
    run_observation_key("cancelled", 9007199254740991L, Some(false), Some(true)),
    Some("cancelled;9007199254740991;0;1"),
  )
}
