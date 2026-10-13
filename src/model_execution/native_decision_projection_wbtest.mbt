///|
fn native_projection_run(
  cursor : NativeDecisionProjection,
  quantum : Int,
) -> NativeDecisionRequest raise {
  for _ in 0..<2000 {
    for _ in 0..<quantum {
      match advance_native_decision_projection(cursor) {
        Ok(Some(value)) => return value
        Ok(None) => ()
        Err(_) => fail("unexpected native projection refusal")
      }
    }
  }
  fail("bounded native projection did not finish")
}

///|
test "native Decision projection preserves original state questions and exact key mapping" {
  let (provider, request, calls) = native_decision_projection_fixture(
    "[\"é\\r\\né\\n😀\",0,false,null,{\"text\":\"\"}]",
  )
  let expected_state = "[\"é\\r\\né\\n😀\",0,false,null,{\"text\":\"\"}]"
  let expected_questions = "{\"q0000000000\":{\"criteria\":{\"o0000000000\":\"toString\",\"o0000000001\":\"__proto__\",\"o0000000002\":\"constructor\"},\"instructions\":\"Choose a routing label.\\r\\né\",\"type\":\"choice\"},\"q0000000001\":{\"criteria\":[\"low\",\"medium\",\"high\"],\"instructions\":\"Score the state.\",\"type\":\"score\"},\"q0000000002\":{\"instructions\":\"P(true) for eligibility.\",\"type\":\"boolean\"}}"
  let mut previous_work = None
  for quantum in [1, 7, 64] {
    let cursor = start_native_decision_projection(
      provider, request, 10000, 1000, 40, 100, 10000,
    ).unwrap()
    let value = native_projection_run(cursor, quantum)
    assert_eq(
      native_decision_request_wires(value),
      Some((expected_state, expected_questions)),
    )
    assert_eq(native_decision_question_id(value, 0), Some("__proto__"))
    assert_eq(native_decision_question_id(value, 1), Some("constructor"))
    assert_eq(native_decision_question_id(value, 2), Some("enabled"))
    assert_eq(native_decision_question_id(value, -1), None)
    assert_eq(native_decision_question_id(value, 3), None)
    assert_eq(native_decision_option_id(value, 0, 0), Some("toString"))
    assert_eq(native_decision_option_id(value, 0, 1), Some("__proto__"))
    assert_eq(native_decision_option_id(value, 0, 2), Some("constructor"))
    assert_eq(native_decision_option_id(value, 1, 0), None)
    assert_true(native_decision_request_matches(value, provider, request))
    let work = native_decision_projection_work(cursor)
    if previous_work is Some(previous) {
      assert_eq(work, previous)
    }
    previous_work = Some(work)
    assert_true(
      physical_equal(
        advance_native_decision_projection(cursor).unwrap().unwrap(),
        value,
      ),
    )
    assert_eq(native_decision_projection_work(cursor), work)
    retire_native_decision_projection(cursor)
    assert_true(cursor.request is None && cursor.questions is None)
    assert_eq(
      native_decision_request_wires(value),
      Some((expected_state, expected_questions)),
    )
    assert_true(native_decision_request_matches(value, provider, request))
    retire_native_decision_request(value)
    retire_native_decision_request(value)
    assert_eq(native_decision_request_wires(value), None)
    assert_eq(native_decision_request_binding(value), None)
    assert_eq(native_decision_question_id(value, 0), None)
    assert_false(native_decision_request_matches(value, provider, request))
  }
  assert_eq(calls(), 0)
}

///|
test "native Decision projection rejects a foreign original and never dispatches" {
  let (provider, request, calls) = native_decision_projection_fixture("null")
  let (foreign_provider, foreign_request, foreign_calls) = native_decision_projection_fixture(
    "null",
  )
  assert_true(
    start_native_decision_projection(
      provider, foreign_request, 10000, 1000, 40, 100, 10000,
    )
    is Err(ForeignRequest),
  )
  let cursor = start_native_decision_projection(
    provider, request, 10000, 1000, 40, 100, 10000,
  ).unwrap()
  let value = native_projection_run(cursor, 1)
  assert_eq(native_decision_request_wires(value).unwrap().0, "null")
  assert_false(
    native_decision_request_matches(value, foreign_provider, request),
  )
  assert_false(
    native_decision_request_matches(value, provider, foreign_request),
  )
  let binding = native_decision_request_binding(value).unwrap()
  assert_eq(
    binding.0,
    "sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e",
  )
  assert_eq(
    binding.1,
    "sha256:3cb49cca43b2ada3360038ff65eb699c5c79e93c2630bd3e3e4ed2fdd980db80",
  )
  assert_eq(
    binding.2,
    "sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9",
  )
  assert_eq(binding.3, "fixture-native")
  retire_native_decision_projection(cursor)
  retire_native_decision_request(value)
  assert_eq(calls(), 0)
  assert_eq(foreign_calls(), 0)
}

///|
test "native Decision projection keeps work exhaustion and interruption on the same child" {
  let (provider, request, calls) = native_decision_projection_fixture(
    "[false,0,\"\"]",
  )
  for ceiling in [0, 1, 12] {
    let cursor = start_native_decision_projection(
      provider, request, 10000, 1000, 40, 100, ceiling,
    ).unwrap()
    for _ in 0..<100 {
      match advance_native_decision_projection(cursor) {
        Err(Limit) => break
        Ok(None) => ()
        _ => fail("unexpected complete native projection")
      }
    }
    assert_true(cursor.phase is Failed(Limit))
    assert_eq(native_decision_projection_work(cursor), ceiling)
    assert_true(cursor.request is None && cursor.questions is None)
    assert_true(advance_native_decision_projection(cursor) is Err(Limit))
  }
  for steps in [0, 2, 12, 32, 80] {
    let cursor = start_native_decision_projection(
      provider, request, 10000, 1000, 40, 100, 10000,
    ).unwrap()
    for _ in 0..<steps {
      assert_true(advance_native_decision_projection(cursor) is Ok(None))
    }
    let work = native_decision_projection_work(cursor)
    retire_native_decision_projection(cursor)
    retire_native_decision_projection(cursor)
    assert_true(
      advance_native_decision_projection(cursor) is Err(ForeignRequest),
    )
    assert_eq(native_decision_projection_work(cursor), work)
    assert_true(
      cursor.state_frames.is_empty() && cursor.question_frames.is_empty(),
    )
  }
  assert_eq(calls(), 0)
}

///|
test "native Decision projection keeps independent wire and workspace ceilings" {
  let (provider, request, calls) = native_decision_projection_fixture(
    "[false,0,\"\"]",
  )
  for
    (bytes, nodes, depth, frames) in [
      (1, 1000, 40, 100),
      (10000, 1, 40, 100),
      (10000, 1000, 1, 100),
      (10000, 1000, 40, 1),
    ] {
    let cursor = start_native_decision_projection(
      provider, request, bytes, nodes, depth, frames, 10000,
    ).unwrap()
    let mut refused = false
    for _ in 0..<2000 {
      match advance_native_decision_projection(cursor) {
        Err(Limit) => {
          refused = true
          break
        }
        Ok(None) => ()
        _ => fail("unexpected complete native projection")
      }
    }
    assert_true(refused)
    assert_true(cursor.request is None && cursor.questions is None)
  }
  assert_eq(calls(), 0)
}

///|
test "native Decision projection exact finite boundaries use independent accounting" {
  let (provider, request, calls) = native_decision_projection_fixture(
    "[false,0,\"\"]",
  )
  // Independent literal wire: 348 UTF-8 bytes, 18 values, maximum depth 3.
  // State: Find(1), checked traversal(9), original wire traversal(8).
  // Questions: Choice(47), Score(35), Boolean(19), list/end(2).
  // Ordered keys each require start plus three bounded emitter transitions.
  // Peak question stack is the 12 explicit continuations of Choice.
  let cursor = start_native_decision_projection(
    provider, request, 348, 18, 3, 12, 121,
  ).unwrap()
  let value = native_projection_run(cursor, 7)
  assert_eq(native_decision_projection_work(cursor), 121)
  assert_eq(native_decision_request_wires(value).unwrap().0, "[false,0,\"\"]")
  retire_native_decision_projection(cursor)
  retire_native_decision_request(value)
  for
    (bytes, nodes, depth, frames, work) in [
      (347, 18, 3, 12, 121),
      (348, 17, 3, 12, 121),
      (348, 18, 2, 12, 121),
      (348, 18, 3, 11, 121),
      (348, 18, 3, 12, 120),
    ] {
    let short = start_native_decision_projection(
      provider, request, bytes, nodes, depth, frames, work,
    ).unwrap()
    let mut refused = false
    for _ in 0..<122 {
      match advance_native_decision_projection(short) {
        Err(Limit) => {
          refused = true
          break
        }
        Ok(None) => ()
        _ => fail("one-short bound unexpectedly completed")
      }
    }
    assert_true(refused)
    assert_true(short.request is None && short.questions is None)
  }
  assert_eq(calls(), 0)
}
