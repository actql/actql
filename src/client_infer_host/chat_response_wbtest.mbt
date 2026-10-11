///|
// Actual original Entry and nominal receipt, with doubled physical bytes/Store
// ACK. These are not real persistence or installed public profile acceptance.
fn install_saved_chat_response_fixture(
  fixture : RawSaveFixture,
  body : String,
) -> Unit {
  let bytes = @utf8.encode(body)
  let save = @model.observe_model_raw_capture(
    fixture.call,
    fixture.registration,
    "sha256:" + @sha.hex(bytes),
    bytes.length(),
    200,
    true,
    "2026-10-02T00:00:00.000Z",
  ).unwrap()
  let receipt = @model.acknowledge_saved_model_raw_capture(save).unwrap()
  fixture.response.val = @model.PhysicalChatResponse(
    @model.model_saved_raw_chat_response(receipt, body, None).unwrap(),
  )
  fixture.ready.val = true
}

///|
test "raw Chat shape refusal retains independently observed usage and cleanup responsibility" {
  for
    body in [
      (
        #|{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2},"opaque":{"original":"é\r\n"}}
      ),
      (
        #|{"usage":{"prompt_tokens":3,"completion_tokens":2},"choices":[{"index":0,"message":{"role":"assistant","content":"null","refusal":"refused"},"finish_reason":"stop"}]}
      ),
    ] {
    let release = Ref(false)
    let cleaned : Array[Bool] = []
    let fixture = raw_save_fixture(cleanup_calls=cleaned, release~)
    install_saved_chat_response_fixture(fixture, body)
    let active = fixture.active
    let prefix = fixture.work
    let calls = fixture.calls
    guard encoded_finish(active, 1, prefix) is Settling(0, work=settled) else {
      abort("classified refusal must retain the original private settlement")
    }
    let original = active.model.unwrap()
    let proof = @model.model_execution_attempt_evidence(original, 0).unwrap()
    let wire = @publication.run_evidence_value_json(
      @model.model_attempt_accounting(proof),
    )
    assert_true(wire.contains("\"input_tokens\":3"))
    assert_true(wire.contains("\"output_tokens\":2"))
    assert_eq(
      @model.model_execution_quantity_usage(original).consumed.tokens,
      5L,
    )
    assert_eq(calls.val, 1)
    assert_true(acquire_output(active) is None)
    assert_true(acquire_capture(active) is None)
    assert_true(cancel(active))
    assert_true(
      @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
    )
    assert_true(fixture_finish(active, initial_work=settled) is AwaitIo(..))
    assert_eq(cleaned, [true])
    assert_true(
      @model.model_execution_resource_usage(original).reserved_retention_bytes >
      0L,
    )
    release.val = true
    assert_true(fixture_finish(active, initial_work=settled) is Stopped(..))
    assert_true(!cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 1)
  }
}

///|
test "raw Chat cancellation after usage scan does not erase or recharge actuals" {
  let body =
    #|{"usage":{"prompt_tokens":3,"completion_tokens":2},"choices":[{"index":0,"message":{"role":"assistant","content":"{\"reason\":null,\"risk\":\"high\"}"},"finish_reason":"stop"}]}
  let cleaned : Array[Bool] = []
  let fixture = raw_save_fixture(cleanup_calls=cleaned)
  install_saved_chat_response_fixture(fixture, body)
  let active = fixture.active
  let prefix = fixture.work
  let calls = fixture.calls
  let original = active.model.unwrap()
  let mut current_work = prefix
  let mut seen = false
  for _ in 0..<8192 {
    guard advance(active, 1).unwrap() is Continue(work~) else {
      abort("usage must be observed before shape/typed answer completion")
    }
    current_work = work
    if @model.model_execution_quantity_usage(original).consumed.tokens == 5L {
      seen = true
      break
    }
  }
  assert_true(seen)
  assert_true(cancel(active))
  guard fixture_finish(active, initial_work=current_work)
    is Settling(0, work=settled) else {
    abort("obtained response must settle before cancellation completes")
  }
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=settled) is Stopped(..))
  let proof = @model.model_execution_attempt_evidence(original, 0).unwrap()
  let wire = @publication.run_evidence_value_json(
    @model.model_attempt_accounting(proof),
  )
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":2"))
  assert_eq(@model.model_execution_quantity_usage(original).consumed.tokens, 5L)
  assert_true(acquire_output(active) is None)
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(@model.model_execution_quantity_usage(original).consumed.tokens, 5L)
  assert_eq(calls.val, 1)
}

///|
test "raw Chat child refuses a foreign receipt even for the same descriptor CID" {
  let body =
    #|{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2}}
  let original = raw_save_fixture()
  let foreign = raw_save_fixture()
  // Both preparations have the same semantic identities and independently
  // entered attempt, but different physical original-call custody.
  install_saved_chat_response_fixture(foreign, body)
  original.response.val = foreign.response.val
  original.ready.val = true
  assert_true(
    fixture_finish(original.active, initial_work=original.work)
    is Failed(Model(@model.OutputIdentity), ..),
  )
  assert_eq(original.calls.val, 1)
  assert_true(acquire_output(original.active) is None)
  assert_true(!cleanup(original.active).unwrap())
  assert_true(cleanup(original.active).unwrap())
  foreign.response.val = @model.PhysicalUnknown({
    input_tokens: None,
    output_tokens: None,
  })
  raw_save_fixture_cleanup(foreign)
}

///|
test "raw Chat success transfers its original saved observation before child retirement" {
  let body =
    #|{"id":"original-request","model":"original-model","usage":{"prompt_tokens":3,"completion_tokens":2},"choices":[{"index":0,"message":{"role":"assistant","content":"{\"reason\":null,\"risk\":\"high\"}"},"finish_reason":"stop"}]}
  let fixture = raw_save_fixture()
  install_saved_chat_response_fixture(fixture, body)
  let active = fixture.active
  guard fixture_finish(active, initial_work=fixture.work)
    is Settling(0, work=settled) else {
    abort("valid saved first-slot answer must settle exactly once")
  }
  let wire = async_settlement_wire(active)
  assert_true(wire.contains("\"response_complete\":true"))
  assert_true(wire.contains("\"provider_request_id\":\"original-request\""))
  assert_true(
    wire.contains("\"provider_reported_model_id\":\"original-model\""),
  )
  assert_true(wire.contains("\"finish_reason\":\"stop\""))
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":2"))
  assert_true(cancel(active))
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=settled) is Stopped(..))
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(fixture.calls.val, 1)
}
