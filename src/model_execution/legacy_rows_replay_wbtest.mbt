///|
test "legacy rows DATA replay keeps original key slot task and input domain checks" {
  let rows = prepared_capacity_test_rows()
  let task = @infer.model_task(@relation.prepared_infer_rows_owner(rows))
  let fixed = "sha256:" + "1".repeat(64)
  let captures : Array[ModelSlotCapture] = []
  // Independently written historical preimages, not the product's request
  // preparation/slot_cid/key_cid helpers or formal evidence reissuance.
  for slot, key in ["a", "b"] {
    let key_wire = "[\"" + key + "\"]"
    let slot_wire = "{\"fixed_request_cid\":\"" +
      fixed +
      "\",\"key\":" +
      key_wire +
      ",\"slot\":" +
      slot.to_string() +
      "}"
    captures.push({
      slot,
      slot_cid: "sha256:" + @sha.hex(@utf8.encode(slot_wire)),
      input_key_cid: "sha256:" + @sha.hex(@utf8.encode(key_wire)),
      fixed_request_cid: fixed,
      provider_id: "models/fixture",
      provider_model: None,
      provider_request_id: None,
      value: model_execution_test_output(task),
      input_tokens: None,
      output_tokens: None,
      observed_at: "2026-10-16T00:00:00.000Z",
    })
  }
  let bundle : ModelCaptureBundle = {
    task_cid: @environment.model_task_identity(task).2,
    fixed_request_cid: fixed,
    captures,
  }
  assert_eq(replay_model_capture_rows(rows, fixed, bundle).unwrap().length(), 2)
  for
    changed in [
      { ..captures[0], input_key_cid: captures[1].input_key_cid, },
      { ..captures[0], slot_cid: captures[1].slot_cid, },
      { ..captures[0], slot: 1, },
      { ..captures[0], fixed_request_cid: "sha256:" + "2".repeat(64), },
      { ..captures[0], provider_id: "models/foreign", },
    ] {
    assert_true(
      replay_model_capture_rows(rows, fixed, {
        ..bundle,
        captures: [changed, captures[1]],
      })
      is Err(OutputIdentity),
    )
  }
  assert_true(
    replay_model_capture_rows(rows, fixed, {
      ..bundle,
      task_cid: "sha256:" + "2".repeat(64),
    })
    is Err(OutputIdentity),
  )
  assert_true(
    replay_model_capture_rows(rows, fixed, {
      ..bundle,
      captures: [captures[1], captures[0]],
    })
    is Err(OutputIdentity),
  )
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
}
