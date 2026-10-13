///|
// Existing checked Program/Model/Entry with nominal raw receipt. The physical
// transport, Store ACK and installation are explicit doubles, not public or
// normal numerical startup acceptance. No caller passes a raw view to this API.
fn finish_stopped_raw_usage_fixture(
  active : Execution,
  slot : Int,
  quantum : Int,
) -> Int64 raise {
  let mut last = 0L
  for _ in 0..<10000 {
    let (complete, work, issue) = advance_stopped_attempt_raw_usage(
      active, slot, quantum,
    ).unwrap()
    assert_true(work >= last && work - last <= quantum.to_int64())
    assert_eq(issue, None)
    last = work
    if complete { return work }
  }
  abort("same original stopped raw reader exceeded its finite fixture ceiling")
}

///|
test "stopped raw Host caller selects original saved native response before immutable proof" {
  let f = native_original_call_fixture()
  let raw = native_original_saved_response(f, 0, native_original_answer(), eof=false)
  f.responses[0] = @model.model_physical_saved_native_response(
    raw, f.views.get(0).unwrap(), f.provider,
    @environment.initial_jev_decision_profile(),
  ).unwrap()
  assert_true(advance_stopped_attempt_raw_usage(f.active, 0, 1)
    is Err(@model.OutputIdentity))
  assert_true(native_original_finish(f.active, f.work)
    is Failed(Model(@model.UnknownCalls), ..))
  assert_true(attempt_evidence(f.active, 0) is Err(@model.OutputIdentity))
  assert_true(advance_stopped_attempt_raw_usage(f.active, 1, 1)
    is Err(@model.OutputIdentity))
  assert_true(advance_stopped_attempt_raw_usage(f.active, 0, 0)
    is Err(@model.InvalidLimits))
  let work = finish_stopped_raw_usage_fixture(f.active, 0, 1)
  assert_true(work > 0L)
  let model = f.active.model.unwrap()
  assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 5L)
  let proof = attempt_evidence(f.active, 0).unwrap()
  let accounting = @publication.run_evidence_value_json(@model.model_attempt_accounting(proof))
  assert_true(accounting.contains("\"input_tokens\":3"))
  assert_true(accounting.contains("\"output_tokens\":2"))
  assert_true(@publication.run_evidence_value_json(@model.model_attempt_outcome(proof))
    .contains("\"category\":\"result_unknown\""))
  assert_eq(advance_stopped_attempt_raw_usage(f.active, 0, 7), Ok((true, work, None)))
  assert_eq(@publication.run_evidence_value_json(
    @model.model_attempt_accounting(attempt_evidence(f.active, 0).unwrap())), accounting)
  assert_true(acquire_output(f.active) is None)
  assert_true(!cleanup(f.active).unwrap())
  f.release.val = true
  assert_true(!cleanup(f.active).unwrap())
  assert_true(cleanup(f.active).unwrap())
  assert_true(advance_stopped_attempt_raw_usage(f.active, 0, 1)
    is Err(@model.OutputIdentity))
  assert_eq(f.sent.val, 1)
}

///|
test "stopped raw Host caller selects saved Chat usage without success or resend" {
  let f = raw_save_fixture()
  let body =
    #|{"usage":{"prompt_tokens":3,"completion_tokens":2},"choices":[],"opaque":"é\r\n"}
  let bytes = @utf8.encode(body)
  let save = @model.observe_model_raw_capture(
    f.call, f.registration, "sha256:" + @sha.hex(bytes), bytes.length(),
    200, false, "2026-10-02T00:00:00.000Z",
  ).unwrap()
  let receipt = @model.acknowledge_saved_model_raw_capture(save).unwrap()
  f.response.val = @model.PhysicalChatResponse(
    @model.model_saved_raw_chat_response(receipt, body, None).unwrap(),
  )
  f.ready.val = true
  assert_true(fixture_finish(f.active, initial_work=f.work)
    is Failed(Model(@model.UnknownCalls), ..))
  let work = finish_stopped_raw_usage_fixture(f.active, 0, 1)
  assert_true(work > 0L)
  let model = f.active.model.unwrap()
  assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 5L)
  let proof = attempt_evidence(f.active, 0).unwrap()
  let wire = @publication.run_evidence_value_json(@model.model_attempt_accounting(proof))
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":2"))
  assert_true(@publication.run_evidence_value_json(@model.model_attempt_outcome(proof))
    .contains("\"category\":\"result_unknown\""))
  assert_eq(advance_stopped_attempt_raw_usage(f.active, 0, 7), Ok((true, work, None)))
  assert_true(acquire_output(f.active) is None)
  assert_true(!cleanup(f.active).unwrap())
  assert_true(cleanup(f.active).unwrap())
  assert_eq(f.calls.val, 1)
}

///|
test "stopped raw Host caller retains nullable original observations on cleanup cancellation" {
  let f = native_original_call_fixture()
  let raw = native_original_saved_response(f, 0, native_original_answer(), eof=false)
  f.responses[0] = @model.model_physical_saved_native_response(
    raw, f.views.get(0).unwrap(), f.provider,
    @environment.initial_jev_decision_profile(),
  ).unwrap()
  assert_true(native_original_finish(f.active, f.work)
    is Failed(Model(@model.UnknownCalls), ..))
  let model = f.active.model.unwrap()
  assert_true(@model.request_model_cancel(model))
  assert_true(advance_stopped_attempt_raw_usage(f.active, 0, 1)
    is Ok((true, _, Some(@model.Cancelled))))
  let proof = attempt_evidence(f.active, 0).unwrap()
  let wire = @publication.run_evidence_value_json(@model.model_attempt_accounting(proof))
  assert_true(wire.contains("\"input_tokens\":null"))
  assert_true(wire.contains("\"output_tokens\":null"))
  assert_true(@publication.run_evidence_value_json(@model.model_attempt_outcome(proof))
    .contains("\"category\":\"result_unknown\""))
  assert_true(advance_stopped_attempt_raw_usage(f.active, 0, 7)
    is Ok((true, _, Some(@model.Cancelled))))
  assert_true(!cleanup(f.active).unwrap())
  f.release.val = true
  assert_true(!cleanup(f.active).unwrap())
  assert_true(cleanup(f.active).unwrap())
  assert_eq(f.sent.val, 1)
}
