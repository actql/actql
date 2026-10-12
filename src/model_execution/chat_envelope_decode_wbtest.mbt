///|
fn chat_test_limits(
  work? : Int = 20000,
) -> @environment.ModelResponseProfileLimits {
  {
    request_bytes: 4096,
    response_bytes: 4096,
    chunk_bytes: 4096,
    chunks: 4,
    header_bytes: 128,
    metadata_bytes: 4096,
    metadata_nodes: 128,
    metadata_depth: 16,
    parse_nodes: 128,
    parse_depth: 16,
    parse_work: work,
    adapter_holding_bytes: 16384,
    adapter_workspace_bytes: 4096,
    active_slots: 1,
    unsettled_slots: 1,
  }
}

///|
fn decode_chat_test(
  body : String,
  quantum? : Int = 1,
) -> Result[(ChatEnvelopeFacts, Int), ModelExecutionIssue] {
  let cursor = start_chat_envelope_decode(body, chat_test_limits()).unwrap()
  let mut work = 0
  for _ in 0..<20000 {
    for _ in 0..<quantum {
      work += 1
      match advance_chat_envelope_decode(cursor) {
        Ok(Some(facts)) => return Ok((facts, work))
        Ok(None) => ()
        Err(issue) => return Err(issue)
      }
    }
  }
  abort("finite codec fixture did not terminate")
}

///|
test "chat envelope preserves original answer and nullable actual metadata at small quanta" {
  let body =
    #|{"id":null,"model":null,"object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"{\"assessment\":\"é\r\n\"}","refusal":null},"finish_reason":"stop"}],"usage":{"prompt_tokens":null,"completion_tokens":7},"opaque":{"__proto__":"original é\r\n"}}
  let (one, work_one) = decode_chat_test(body).unwrap()
  let (seven, work_seven) = decode_chat_test(body, quantum=7).unwrap()
  assert_true(chat_envelope_complete(one))
  assert_true(chat_envelope_complete(seven))
  assert_eq(work_one, work_seven)
  assert_eq(one.answer, Some("{\"assessment\":\"é\r\n\"}"))
  assert_eq(seven.answer, one.answer)
  assert_eq(one.provider_model, None)
  assert_eq(one.provider_request_id, None)
  assert_eq(one.input_tokens, None)
  assert_eq(one.output_tokens, Some(7L))
  // Full unknown-data preservation belongs to the original entered raw
  // terminal/Artifact, exercised by the actual Model caller regression.
}

///|
test "chat envelope rejection retains observed usage regardless of field order" {
  for
    body in [
      (
        #|{"choices":[],"usage":{"prompt_tokens":3}}
      ),
      (
        #|{"usage":{"prompt_tokens":3},"choices":[{},{}]}
      ),
      (
        #|{"choices":[{"index":1,"message":{"role":"assistant","content":"null"},"finish_reason":"stop"}],"usage":{"prompt_tokens":3}}
      ),
      (
        #|{"choices":[{"index":0,"message":{"role":"assistant","content":"null","refusal":"refused"},"finish_reason":"stop"}],"usage":{"prompt_tokens":3}}
      ),
      (
        #|{"choices":[{"index":0,"message":{"role":"assistant","content":"null"},"finish_reason":"length"}],"usage":{"prompt_tokens":3}}
      ),
      (
        #|{"choices":[{"index":0,"message":{"role":"assistant","content":"null"},"finish_reason":"future_unknown"}],"usage":{"prompt_tokens":3}}
      ),
      (
        #|{"choices":[{"index":0,"message":{"role":"assistant","content":"null","tool_calls":[{}]},"finish_reason":"stop"}],"usage":{"prompt_tokens":3}}
      ),
    ] {
    let (facts, _) = decode_chat_test(body).unwrap()
    assert_false(chat_envelope_complete(facts))
    assert_eq(facts.input_tokens, Some(3L))
    assert_eq(facts.output_tokens, None)
  }
}

///|
test "chat envelope distinguishes missing values from known zero and refuses invalid observations" {
  let absent =
    #|{"choices":[{"index":0,"message":{"role":"assistant","content":"null"},"finish_reason":"stop"}]}
  let (facts, _) = decode_chat_test(absent).unwrap()
  assert_true(chat_envelope_complete(facts))
  assert_eq(facts.provider_model, None)
  assert_eq(facts.input_tokens, None)
  let exact =
    #|{"id":"original-id","model":"actually-reported-model","choices":[{"index":0,"message":{"role":"assistant","content":"null"},"finish_reason":"stop"}],"usage":{"prompt_tokens":0,"completion_tokens":9007199254740991}}
  let (facts, _) = decode_chat_test(exact).unwrap()
  assert_true(chat_envelope_complete(facts))
  assert_eq(facts.provider_model, Some("actually-reported-model"))
  assert_eq(facts.provider_request_id, Some("original-id"))
  assert_eq(facts.input_tokens, Some(0L))
  assert_eq(facts.output_tokens, Some(9007199254740991L))
  for
    body in [
      (
        #|{"choices":[{"index":0,"message":{"role":"assistant","content":"null"},"finish_reason":"stop"}],"usage":{"prompt_tokens":-1,"completion_tokens":2}}
      ),
      (
        #|{"choices":[{"index":0,"message":{"role":"assistant","content":"null"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1.5,"completion_tokens":2}}
      ),
      (
        #|{"model":"","choices":[{"index":0,"message":{"role":"assistant","content":"null"},"finish_reason":"stop"}],"usage":{"completion_tokens":2}}
      ),
    ] {
    let (facts, _) = decode_chat_test(body).unwrap()
    assert_false(chat_envelope_complete(facts))
    assert_eq(facts.input_tokens, None)
    assert_eq(facts.output_tokens, Some(2L))
  }
}

///|
test "chat envelope parser rejects malformed originals and codec refuses unsafe usage" {
  for
    body in [
      "{", "{\"unknown\":1,\"unknown\":2}", "{\"opaque\":\"\\ud800\"}", "null",
    ] {
    assert_true(decode_chat_test(body) is Err(OutputValue))
  }
  // 2^53 is representable JSON but outside the exact safe token domain.
  // Reject the usage observation, not the entire JSON grammar as malformed.
  let (outside_domain, _) = decode_chat_test(
    "{\"usage\":{\"prompt_tokens\":9007199254740992}}",
  ).unwrap()
  assert_false(chat_envelope_complete(outside_domain))
  assert_true(outside_domain.malformed)
  assert_eq(outside_domain.input_tokens, None)
}

///|
test "chat envelope original work and cancellation retire parser without restart" {
  let cursor = start_chat_envelope_decode("{}", chat_test_limits(work=1)).unwrap()
  assert_true(advance_chat_envelope_decode(cursor) is Ok(None))
  assert_true(advance_chat_envelope_decode(cursor) is Err(WorkLimit))
  assert_true(cursor.phase is ChatReclaimed)
  assert_eq(cursor.frames.length(), 0)
  assert_true(cursor.facts is None)
  let cancelled = start_chat_envelope_decode("{}", chat_test_limits()).unwrap()
  assert_true(advance_chat_envelope_decode(cancelled) is Ok(None))
  cancel_chat_envelope_decode(cancelled)
  cancel_chat_envelope_decode(cancelled)
  assert_true(advance_chat_envelope_decode(cancelled) is Err(OutputIdentity))
}

///|
test "chat envelope field scan exact work is one field plus retirement and transfer" {
  let source = @source.parse_json("{\"id\":null}", {
    max_input_bytes: 11,
    max_nodes: 2,
    max_depth: 2,
  }).unwrap()
  let original = @decode.admit(source, {
    max_nodes: 2,
    max_depth: 2,
    max_string_bytes: 2,
    max_total_string_bytes: 2,
  }).unwrap()
  for work in [2, 3] {
    let cursor : ChatEnvelopeDecode = {
      phase: ScanChat,
      limits: chat_test_limits(work~),
      remaining: work,
      frames: [{ source: original, role: RootEnvelope, next: 0, }],
      facts: Some({
        answer: None,
        provider_model: None,
        provider_request_id: None,
        input_tokens: None,
        output_tokens: None,
        finish_reason: None,
        choices_seen: false,
        index_seen: false,
        message_seen: false,
        role_seen: false,
        refused: false,
        malformed: false,
      }),
    }
    assert_true(advance_chat_envelope_decode(cursor) is Ok(None))
    assert_true(advance_chat_envelope_decode(cursor) is Ok(None))
    if work == 3 {
      assert_true(advance_chat_envelope_decode(cursor) is Ok(Some(_)))
      assert_eq(cursor.remaining, 0)
    } else {
      assert_true(advance_chat_envelope_decode(cursor) is Err(WorkLimit))
    }
    assert_true(cursor.phase is ChatReclaimed)
    assert_eq(cursor.frames.length(), 0)
    assert_true(cursor.facts is None)
  }
}
