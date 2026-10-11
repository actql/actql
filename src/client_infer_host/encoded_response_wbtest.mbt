///|
fn encoded_response(body : String) -> @model.ModelPhysicalCallPoll {
  let original = async_response_observation(None)
  @model.PhysicalEncodedResponse({
    body,
    observation: original.observation,
    transport_eof: true,
    endpoint_complete: true,
    answer_complete: true,
  })
}

///|
// One declared 8192-transition parse budget plus the existing finite 2000
// response/evidence allowance and 2000 Host transitions. This loop ceiling
// does not increase the profile, Run work limit, bytes or allocation bounds.
fn encoded_finish(
  active : Execution,
  quantum : Int,
  work : Int64,
) -> Poll raise {
  let mut last = work
  for _ in 0..<12192 {
    let poll = advance(active, quantum).unwrap()
    let total = match poll {
      Continue(work~)
      | AwaitIo(work~)
      | Waiting(work~)
      | Settling(_, work~)
      | Complete(_, work~)
      | Failed(_, work~)
      | Stopped(work~) => work
    }
    assert_true(total >= last && total - last <= quantum.to_int64())
    last = total
    if !(poll is Continue(_)) {
      return poll
    }
  }
  abort("declared bounded answer and Host transition allowance")
}

///|
fn finish_encoded_case(
  body : String,
  quantum : Int,
) -> (Array[String], Int64) raise {
  let calls = Ref(0)
  let cleaned : Array[Bool] = []
  let (active, prefix) = async_response_fixture(
    calls,
    Ref(0),
    Ref(0),
    cleaned,
    Ref(true),
    Ref(true),
    encoded_response(body),
  )
  let wires : Array[String] = []
  let mut total = prefix
  for slot in 0..<2 {
    guard encoded_finish(active, quantum, total) is Settling(index, work~) else {
      abort("encoded response must settle the original slot")
    }
    assert_eq(index, slot)
    wires.push(async_settlement_wire(active))
    total = work
    assert_true(
      @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
    )
  }
  guard encoded_finish(active, quantum, total) is Complete(_, work~) else {
    abort("original encoded slots must complete")
  }
  assert_eq(calls.val, 2)
  assert_eq(cleaned, [true, true])
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  (wires, work)
}

///|
test "encoded physical answer uses common bounded cursors and preserves raw Unicode and newlines" {
  let body =
    #|{"risk":"high","reason":"é\r\n\n"}
  let (one, work_one) = finish_encoded_case(body, 1)
  let (seven, work_seven) = finish_encoded_case(body, 7)
  assert_eq(one, seven)
  assert_eq(work_one, work_seven)
  for wire in one {
    assert_true(
      wire.contains(
        "\"structured_response\":{\"reason\":\"é\\r\\n\\n\",\"risk\":\"high\"}",
      ),
    )
    assert_true(wire.contains("\"provider_metadata\":null"))
    assert_true(wire.contains("\"input_tokens\":null"))
    assert_true(wire.contains("actql-model-invocation-evidence/0.2"))
  }
}

///|
test "encoded physical answer retains the exact profile byte boundary" {
  let answer = "{\"reason\":null,\"risk\":\"high\"}"
  let at_limit = StringBuilder()
  at_limit.write_string(answer)
  for _ in answer.length()..<2048 {
    at_limit.write_string(" ")
  }
  let (wires, _) = finish_encoded_case(at_limit.to_string(), 7)
  assert_eq(wires.length(), 2)
  let calls = Ref(0)
  let (active, prefix) = async_response_fixture(
    calls,
    Ref(0),
    Ref(0),
    [],
    Ref(true),
    Ref(true),
    encoded_response(at_limit.to_string() + " "),
  )
  // The finite independent ceiling here permits the declared 2048 bytes;
  // the byte ceiling is not increased to accept the negative case.
  guard encoded_finish(active, 7, prefix) is Failed(_, ..) else {
    abort("one byte above the original profile must fail")
  }
  assert_eq(calls.val, 1)
  assert_true(call_settlement(active) is None)
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "encoded malformed and wrong typed answers do not publish or enter another slot" {
  for
    body in [
      "{", "null", "{\"risk\":\"high\"}", "{\"reason\":null,\"risk\":false}", "{\"reason\":null,\"risk\":\"high\",\"extra\":0}",
      "{\"reason\":null,\"risk\":\"high\",\"risk\":\"low\"}", "{\"reason\":\"\\ud800\",\"risk\":\"high\"}",
    ] {
    let calls = Ref(0)
    let (active, prefix) = async_response_fixture(
      calls,
      Ref(0),
      Ref(0),
      [],
      Ref(true),
      Ref(true),
      encoded_response(body),
    )
    guard async_finish_quantum(active, 1, prefix) is Failed(_, ..) else {
      abort("malformed or output-contract violation must fail")
    }
    assert_eq(calls.val, 1)
    assert_true(call_settlement(active) is None)
    assert_true(!cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "cancel during bounded answer parsing retains original settlement without resending" {
  let calls = Ref(0)
  let cancels = Ref(0)
  let cleaned : Array[Bool] = []
  let ready = Ref(false)
  let (active, prefix) = async_response_fixture(
    calls,
    Ref(0),
    cancels,
    cleaned,
    ready,
    Ref(true),
    encoded_response("{\"reason\":null,\"risk\":\"high\"}"),
  )
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("original response must initially be pending")
  }
  ready.val = true
  guard advance(active, 1).unwrap() is Continue(work=begun) else {
    abort("start bounded answer decoding")
  }
  assert_eq(begun, work + 1L)
  guard advance(active, 1).unwrap() is Continue(work=parsing) else {
    abort("decode one bounded answer transition")
  }
  assert_eq(parsing, begun + 1L)
  assert_true(cancel(active))
  guard fixture_finish(active, initial_work=parsing)
    is Settling(0, work=settled) else {
    abort("already obtained response must settle before cancellation")
  }
  assert_true(async_settlement_wire(active).contains("\"risk\":\"high\""))
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=settled) is Stopped(..))
  assert_eq(calls.val, 1)
  assert_eq(cleaned, [true])
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "answer parse failure preserves observed usage and original cleanup retry" {
  let calls = Ref(0)
  let release = Ref(false)
  let cleaned : Array[Bool] = []
  let response = async_response_observation(None)
  let observed = @model.PhysicalEncodedResponse({
    body: "{",
    observation: {
      ..response.observation,
      input_tokens: Some(3L),
      output_tokens: Some(2L),
    },
    transport_eof: true,
    endpoint_complete: true,
    answer_complete: true,
  })
  let (active, prefix) = async_response_fixture(
    calls,
    Ref(0),
    Ref(0),
    cleaned,
    Ref(true),
    release,
    observed,
  )
  assert_true(
    encoded_finish(active, 1, prefix) is Failed(Model(@model.OutputValue), ..),
  )
  let original = active.model.unwrap()
  let evidence = @model.model_execution_attempt_evidence(original, 0).unwrap()
  let accounting = @publication.run_evidence_value_json(
    @model.model_attempt_accounting(evidence),
  )
  assert_true(accounting.contains("\"input_tokens\":3"))
  assert_true(accounting.contains("\"output_tokens\":2"))
  assert_eq(@model.model_execution_quantity_usage(original).consumed.tokens, 5L)
  assert_true(acquire_output(active) is None)
  assert_true(acquire_capture(active) is None)
  assert_true(!cleanup(active).unwrap())
  assert_eq(cleaned, [false])
  assert_true(
    @model.model_execution_resource_usage(original).reserved_retention_bytes >
    0L,
  )
  release.val = true
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
  assert_eq(
    @model.model_execution_resource_usage(original).reserved_retention_bytes,
    0L,
  )
}
