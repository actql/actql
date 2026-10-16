///|
test "same Run continuation retains the admitted observation revision without issuing one" {
  let legacy =
    #|{"version":"actql-run-state/0.1","run_id":"original-run","status":"succeeded","updated_at":"2026-10-17T00:00:00.000Z","next_action":{"kind":"read_result","results":["answer"]},"result_available":true,"result_availability":{"answer":{"state":"available","reason":"confirmed_present","observed_at":"2026-10-17T00:00:00.000Z"}}}
  let limits : WireLimits = {
    max_wire_bytes: 8192,
    max_nodes: 128,
    max_depth: 16,
  }
  let original = admit_run_state_wire(legacy, limits).unwrap()
  assert_false(original.wire.contains("\"revision\""))
  for revision in ["0", "4", "9007199254740991"] {
    let wire = "{\"revision\":" + revision + "," + legacy[1:]
    let admitted = admit_run_state_wire(wire, limits).unwrap()
    assert_eq(admitted.run_id, "original-run")
    assert_eq(admitted.status, Succeeded)
    assert_true(admitted.wire.contains("\"revision\":" + revision + ","))
  }
  for invalid in ["-1", "0.5", "9007199254740992", "null", "\"4\""] {
    let wire = "{\"revision\":" + invalid + "," + legacy[1:]
    assert_true(admit_run_state_wire(wire, limits) is Err(_))
  }
  assert_true(
    admit_run_state_wire("{\"other_counter\":4," + legacy[1:], limits) is Err(_),
  )
}
