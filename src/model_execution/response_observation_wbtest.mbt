///|
test "metadata emission cancellation retires its cursor and original writer" {
  let task = @environment.resolve_model_task(
    model_execution_test_tasks(), "model-task:risk-score.v1",
  ).unwrap()
  let checked = model_execution_test_output(task)
  let response = lift_historical_model_response({
    value: checked.value,
    provider_model: "historical-model",
    provider_request_id: "historical-request",
    input_tokens: 0L,
    output_tokens: 0L,
    observed_at: "2026-10-11T00:00:00.000Z",
  })
  let metadata = @canonical.from_json(
    Json::object({ "opaque": Json::string("e\u0301\r\n".repeat(100)) }), 32, 8, 4096,
  )
  let writer = @encode.writer(4096, 32, 8)
  @encode.begin_object(writer)
  @encode.key(writer, "provider_metadata")
  let cursor = @canonical.start_emit(metadata, writer)
  assert_true(!@canonical.advance_emit(cursor))
  assert_true(!@canonical.advance_emit(cursor))
  let pending : ModelEvidencePreparation = {
    request: {
      task, slot: 0, slot_cid: "sha256:" + "1".repeat(64),
      fixed_request_cid: "sha256:" + "2".repeat(64), key: [], inputs: [],
    },
    response,
    key_cid: "sha256:" + "3".repeat(64),
    checked,
    response_cid: None,
    output_cid: None,
    phase: Metadata(cursor, writer),
  }
  cancel_model_evidence(pending)
  assert_eq(@canonical.emit_pending_frames(cursor), 0)
  let finished = try @encode.finish(writer) catch { _ => "cancelled" }
  assert_eq(finished, "cancelled")
  cancel_model_evidence(pending)
  assert_eq(@canonical.emit_pending_frames(cursor), 0)
}
