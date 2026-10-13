///|
fn native_envelope_test(
  body : String,
) -> (NativeEnvelopeDecode, @decode.Cursor) {
  let child = start_native_envelope_decode(body, chat_test_limits()).unwrap()
  for _ in 0..<20000 {
    match advance_native_envelope_decode(child) {
      Ok(None) => ()
      Ok(Some(root)) => return (child, root)
      Err(_) => abort("finite original native envelope did not decode")
    }
  }
  abort("native child did not finish")
}

///|
fn native_answer_child_fixture(
  original : NativeDecisionRequest,
  wire : String,
  work : Int,
) -> ModelResponseDecode {
  {
    phase: ParseNativeAnswer(
      @source.start_json_parse(
        wire,
        { max_input_bytes: 4096, max_nodes: 128, max_depth: 16, },
        data_keys=true,
      ).unwrap(),
      original,
      @environment.initial_jev_decision_profile(),
    ),
    limits: chat_test_limits(),
    remaining: work,
    raw_chat: None,
    observation: None,
  }
}

///|
fn native_answer_child_finish(
  cursor : ModelResponseDecode,
  task : @environment.ModelTaskContract,
) -> Result[@admitted.CheckedValue, ModelExecutionIssue] {
  for _ in 0..<20000 {
    match
      advance_model_response_decode(
        cursor,
        @environment.model_task_output(task),
        { max_nodes: 128, max_depth: 16, max_text_bytes: 4096, },
      ) {
      Ok(None) => ()
      Ok(Some(value)) => return Ok(value)
      Err(issue) => return Err(issue)
    }
  }
  abort("finite answer child did not terminate")
}

///|
test "native response child missing known zero malformed usage and partial stop remain distinct" {
  for wire in ["{}", "{\"usage\":null}"] {
    let (child, _) = native_envelope_test(wire)
    assert_eq(child.facts.unwrap().input_tokens, None)
    assert_eq(child.facts.unwrap().output_tokens, None)
    cancel_native_envelope_decode(child)
  }
  let (exact, _) = native_envelope_test(
    "{\"usage\":{\"input_tokens\":0,\"output_tokens\":9007199254740991}}",
  )
  assert_eq(exact.facts.unwrap().input_tokens, Some(0L))
  assert_eq(exact.facts.unwrap().output_tokens, Some(9007199254740991L))
  cancel_native_envelope_decode(exact)
  for bad in ["-1", "0.5", "9007199254740992"] {
    let (child, _) = native_envelope_test(
      "{\"usage\":{\"input_tokens\":3,\"output_tokens\":" + bad + "}}",
    )
    assert_true(child.facts.unwrap().malformed)
    assert_eq(child.facts.unwrap().input_tokens, Some(3L))
    assert_eq(child.facts.unwrap().output_tokens, None)
    cancel_native_envelope_decode(child)
  }
  let child = start_native_envelope_decode(
    "{\"usage\":{\"input_tokens\":3},\"answers\":{}}",
    chat_test_limits(),
  ).unwrap()
  for _ in 0..<20000 {
    assert_true(advance_native_envelope_decode(child) is Ok(None))
    if child.facts is Some(facts) && facts.input_tokens == Some(3L) {
      break
    }
  }
  assert_eq(child.facts.unwrap().input_tokens, Some(3L))
  assert_eq(child.facts.unwrap().output_tokens, None)
  // Actual partials transfer to the original attempt before child retirement;
  // cancelling this child does not constitute physical stop or saved success.
  cancel_native_envelope_decode(child)
  assert_true(advance_native_envelope_decode(child) is Err(OutputIdentity))
}

///|
test "native response child rejects grid maximum and retired original without generation fallback" {
  let (provider, request, original, calls) = native_plan_original()
  for
    raw in [
      native_answer_fixture_wire().replace(
        old="\"noul\":0.25",
        new="\"noul\":0.251",
      ),
      native_answer_fixture_wire().replace(
        old="\"o0000000000\":0.33",
        new="\"o0000000000\":0.34",
      ),
    ] {
    let (child, root) = native_envelope_test(raw)
    let (wire, _) = project_native_decision_answers(
      original,
      provider,
      request,
      root,
      4096,
      128,
      16,
      child.remaining,
    ).unwrap()
    let answer = native_answer_child_fixture(original, wire, child.remaining)
    assert_true(
      native_answer_child_finish(answer, request.task) is Err(OutputValue),
    )
    cancel_model_response_decode(answer)
    cancel_native_envelope_decode(child)
  }
  let (envelope, root) = native_envelope_test(native_answer_fixture_wire())
  let (wire, _) = project_native_decision_answers(
    original,
    provider,
    request,
    root,
    4096,
    128,
    16,
    envelope.remaining,
  ).unwrap()
  let answer = native_answer_child_fixture(original, wire, envelope.remaining)
  retire_native_decision_request(original)
  assert_true(
    native_answer_child_finish(answer, request.task) is Err(RequestIdentity),
  )
  cancel_model_response_decode(answer)
  cancel_native_envelope_decode(envelope)
  assert_eq(calls(), 0)
}

///|
test "native response child exact work exhaustion and cancellation cannot restart or reset" {
  let child = start_native_envelope_decode("{}", chat_test_limits(work=1)).unwrap()
  assert_true(advance_native_envelope_decode(child) is Ok(None))
  assert_true(advance_native_envelope_decode(child) is Err(WorkLimit))
  assert_eq(child.remaining, 0)
  assert_true(child.phase is NativeEnvelopeRetired)
  let (provider, request, original, calls) = native_plan_original()
  let (envelope, root) = native_envelope_test(native_answer_fixture_wire())
  let (wire, _) = project_native_decision_answers(
    original,
    provider,
    request,
    root,
    4096,
    128,
    16,
    envelope.remaining,
  ).unwrap()
  let short = native_answer_child_fixture(original, wire, 1)
  assert_true(
    advance_model_response_decode(
      short,
      @environment.model_task_output(request.task),
      { max_nodes: 128, max_depth: 16, max_text_bytes: 4096, },
    )
    is Ok(None),
  )
  assert_true(native_answer_child_finish(short, request.task) is Err(WorkLimit))
  assert_eq(short.remaining, 0)
  let cancelled = native_answer_child_fixture(original, wire, 10000)
  let remaining = cancelled.remaining
  cancel_model_response_decode(cancelled)
  cancel_model_response_decode(cancelled)
  assert_true(
    native_answer_child_finish(cancelled, request.task) is Err(OutputIdentity),
  )
  assert_eq(cancelled.remaining, remaining)
  cancel_native_envelope_decode(envelope)
  retire_native_decision_request(original)
  assert_eq(calls(), 0)
}

///|
test "native response child preserves original unknown data and nullable observed usage" {
  let wire =
    #|{"model":null,"id":null,"usage":{"input_tokens":null,"output_tokens":7},"answers":{},"opaque":{"original":"é\r\n","confidence":0.9}}
  let (child, root) = native_envelope_test(wire)
  let facts = child.facts.unwrap()
  assert_eq(facts.provider_model, None)
  assert_eq(facts.provider_request_id, None)
  assert_eq(facts.input_tokens, None)
  assert_eq(facts.output_tokens, Some(7L))
  assert_eq(facts.finish_reason, None)
  assert_false(facts.malformed)
  assert_true(native_decision_field(root, "opaque") is Some(_))
  assert_true(advance_native_envelope_decode(child) is Err(OutputIdentity))
  cancel_native_envelope_decode(child)
  assert_true(child.facts is None)
  assert_true(child.frames.is_empty())
  assert_true(child.phase is NativeEnvelopeRetired)
}

///|
test "native response child maps original aliases validates distribution and types answer" {
  let (provider, request, original, calls) = native_plan_original()
  let (envelope, root) = native_envelope_test(native_answer_fixture_wire())
  let (wire, work) = project_native_decision_answers(
    original,
    provider,
    request,
    root,
    4096,
    128,
    16,
    envelope.remaining,
  ).unwrap()
  // Independent original-ID answer, never generated from the product output.
  let expected = "{\"__proto__\":{\"choice\":\"__proto__\",\"probabilities\":[{\"option\":\"toString\",\"probability\":0.33},{\"option\":\"__proto__\",\"probability\":0.33},{\"option\":\"constructor\",\"probability\":0.33}]},\"constructor\":{\"probabilities\":[{\"level\":0,\"probability\":0},{\"level\":1,\"probability\":0.5},{\"level\":2,\"probability\":0.5}],\"score\":1.5},\"enabled\":{\"probability\":0.25}}"
  assert_eq(wire, expected)
  assert_eq(work, 455)
  // No saved receipt or installation is manufactured by this isolated child
  // fixture. Original Call/Entry/receipt binding is a separate runtime gate.
  let cursor : ModelResponseDecode = {
    phase: ParseNativeAnswer(
      @source.start_json_parse(
        wire,
        { max_input_bytes: 4096, max_nodes: 128, max_depth: 16, },
        data_keys=true,
      ).unwrap(),
      original,
      @environment.initial_jev_decision_profile(),
    ),
    limits: chat_test_limits(),
    remaining: envelope.remaining - work,
    raw_chat: None,
    observation: None,
  }
  let mut completed = false
  for _ in 0..<20000 {
    match
      advance_model_response_decode(
        cursor,
        @environment.model_task_output(request.task),
        { max_nodes: 128, max_depth: 16, max_text_bytes: 4096, },
      ) {
      Ok(None) => ()
      Ok(Some(checked)) => {
        let writer = @encode.writer(4096, 128, 16)
        @admitted.emit_checked_wire_value(checked, writer)
        assert_eq(@encode.finish(writer), expected)
        completed = true
        break
      }
      Err(_) => abort("existing native answer child must type-check")
    }
  }
  assert_true(completed)
  assert_true(cursor.phase is DecodeReclaimed)
  cancel_native_envelope_decode(envelope)
  retire_native_decision_request(original)
  assert_eq(calls(), 0)
}

///|
test "native response profile probability remains a task-bound data check not a receipt" {
  let (_, request, original, calls) = native_plan_original()
  assert_true(
    @environment.check_model_response_profile_probability(
      native_plan_profile(),
      request.task,
      @environment.initial_jev_decision_profile(),
    )
    is Ok(_),
  )
  let old_task = @environment.resolve_model_task(
    model_execution_test_tasks(),
    "model-task:risk-score.v1",
  ).unwrap()
  assert_true(
    @environment.check_model_response_profile_probability(
      native_plan_profile(),
      old_task,
      @environment.initial_jev_decision_profile(),
    )
    is Err(_),
  )
  retire_native_decision_request(original)
  assert_eq(calls(), 0)
}
