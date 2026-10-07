///|
test "Run reconciliation action retains execution unknown without inventing Effects" {
  let wire =
    #|{"version":"actql-run-state/0.1","run_id":"original-run","status":"needs_reconciliation","updated_at":"2026-10-07T00:00:00.000Z","next_action":{"kind":"reconcile_run","reason":"execution_unknown"},"result_available":false,"result_availability":{"answer":{"state":"unavailable","reason":"not_published","observed_at":"2026-10-07T00:00:00.000Z"}}}
  let limits : WireLimits = {
    max_wire_bytes: 8192,
    max_nodes: 128,
    max_depth: 16,
  }
  let admitted = admit_run_state_wire(wire, limits).unwrap()
  assert_eq(admitted.run_id, "original-run")
  assert_eq(admitted.status, NeedsReconciliation)
  assert_eq(admitted.checkpoint_cid, None)
  assert_true(admitted.wire.contains("\"kind\":\"reconcile_run\""))
  assert_false(admitted.wire.contains("\"effects\""))
  for
    (old, new) in [
      ("execution_unknown", "unknown_reason"),
      ("\"reason\":\"execution_unknown\"", "\"effects\":[]"),
      ("needs_reconciliation", "cancelled"),
      ("needs_reconciliation", "succeeded"),
    ] {
    assert_true(
      admit_run_state_wire(wire.replace(old~, new~), limits) is Err(_),
    )
  }
}
