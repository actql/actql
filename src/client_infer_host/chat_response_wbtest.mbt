///|
// Physical observations are doubles, not authenticated Store artifacts or
// permission to advertise an installed public RawChat provider. These cases
// exercise refusal/cancellation accounting on the original response child.
fn chat_response_failure_fixture(body : String) -> @model.ModelPhysicalCallPoll {
  @model.PhysicalChatResponse({
    body,
    status: 200,
    transport_eof: true,
    raw_response_artifact_cid: "sha256:" + @sha.hex(@utf8.encode(body)),
    observed_at: "2026-10-02T00:00:00.000Z",
    provider_metadata: None,
  })
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
    let calls = Ref(0)
    let release = Ref(false)
    let cleaned : Array[Bool] = []
    let (active, prefix) = async_response_fixture(
      calls,
      Ref(0),
      Ref(0),
      cleaned,
      Ref(true),
      release,
      chat_response_failure_fixture(body),
    )
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
  let calls = Ref(0)
  let cleaned : Array[Bool] = []
  let (active, prefix) = async_response_fixture(
    calls,
    Ref(0),
    Ref(0),
    cleaned,
    Ref(true),
    Ref(true),
    chat_response_failure_fixture(body),
  )
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
