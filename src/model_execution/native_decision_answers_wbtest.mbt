///|
fn native_answer_fixture_source(wire : String) -> @decode.Cursor {
  let parse = @source.start_json_parse(wire, {
    max_input_bytes: 10000, max_nodes: 1000, max_depth: 40,
  }, data_keys=true).unwrap()
  for _ in 0..<10000 {
    match @source.advance_json_parse(parse, 1) {
      Ok(@source.JsonParseComplete(value, ..)) =>
        return @decode.admit(value.node, {
          max_nodes: 1000, max_depth: 40,
          max_string_bytes: 10000, max_total_string_bytes: 10000,
        }).unwrap()
      Ok(@source.JsonParseContinue(..)) => ()
      _ => abort("independent native answer fixture parse failed")
    }
  }
  abort("finite fixture parse did not finish")
}

///|
fn native_answer_fixture_wire() -> String {
  // Deliberately reversed question/option enumeration and unknown metadata.
  "{\"answers\":{\"q0000000002\":{\"type\":\"noul\",\"noul\":0.25},\"q0000000001\":{\"type\":\"score\",\"score\":1.5,\"probabilities\":{\"2\":0.5,\"0\":0,\"1\":0.5}},\"q0000000000\":{\"type\":\"choice\",\"choice\":\"o0000000001\",\"probabilities\":{\"o0000000002\":0.33,\"o0000000001\":0.33,\"o0000000000\":0.33},\"confidence\":0.9}},\"unknown\":{\"text\":\"é\\r\\n\"}}"
}

///|
test "native answers map original IDs and original distribution order without rewriting ties" {
  let (provider, request, calls) = native_decision_projection_fixture("null")
  let cursor = start_native_decision_projection(provider, request, 10000, 1000, 40, 100, 10000).unwrap()
  let original = native_projection_run(cursor, 1)
  let response = native_answer_fixture_source(native_answer_fixture_wire())
  let (wire, work) = project_native_decision_answers(original, provider, request,
    response, 10000, 1000, 40, 10000).unwrap()
  let expected = "{\"__proto__\":{\"choice\":\"__proto__\",\"probabilities\":[{\"option\":\"toString\",\"probability\":0.33},{\"option\":\"__proto__\",\"probability\":0.33},{\"option\":\"constructor\",\"probability\":0.33}]},\"constructor\":{\"probabilities\":[{\"level\":0,\"probability\":0},{\"level\":1,\"probability\":0.5},{\"level\":2,\"probability\":0.5}],\"score\":1.5},\"enabled\":{\"probability\":0.25}}"
  assert_eq(wire, expected)
  assert_true(work > 0)
  // Mapping is not admission. The existing validator independently checks the
  // selected physical precision, maximum/tie and weighted Score rules.
  assert_true(@environment.validate_decision_answers(original.decision.unwrap(),
    native_answer_fixture_source(wire), @environment.initial_jev_decision_profile(),
    10000) is Ok(_))
  assert_true(native_decision_field(response, "unknown") is Some(_))
  assert_eq(calls(), 0)
  retire_native_decision_projection(cursor)
  retire_native_decision_request(original)
}

///|
test "native answer projection refuses foreign and retired originals without provider invocation" {
  let (provider, request, calls) = native_decision_projection_fixture("null")
  let (foreign, foreign_request, foreign_calls) = native_decision_projection_fixture("null")
  let cursor = start_native_decision_projection(provider, request, 10000, 1000, 40, 100, 10000).unwrap()
  let original = native_projection_run(cursor, 1)
  let raw = native_answer_fixture_source(native_answer_fixture_wire())
  for (p, r) in [(foreign, request), (provider, foreign_request)] {
    assert_true(project_native_decision_answers(original, p, r, raw, 10000, 1000, 40, 10000) is Err(ForeignRequest))
  }
  retire_native_decision_request(original)
  assert_true(project_native_decision_answers(original, provider, request, raw,
    10000, 1000, 40, 10000) is Err(ForeignRequest))
  assert_eq(calls(), 0)
  assert_eq(foreign_calls(), 0)
  retire_native_decision_projection(cursor)
}

///|
test "native answer aliases missing extra or wrong kind refuse rather than synthesize answers" {
  let (provider, request, calls) = native_decision_projection_fixture("null")
  let cursor = start_native_decision_projection(provider, request, 10000, 1000, 40, 100, 10000).unwrap()
  let original = native_projection_run(cursor, 1)
  for wire in ["{}", "{\"answers\":{}}", "{\"answers\":null}",
      "{\"answers\":{\"wrong\":{},\"q0000000001\":{},\"q0000000002\":{}}}",
      native_answer_fixture_wire().replace(old="o0000000001\",\"probabilities", new="o9999999999\",\"probabilities"),
      native_answer_fixture_wire().replace(old="\"noul\",\"noul\"", new="\"boolean\",\"noul\""),
      native_answer_fixture_wire().replace(old="\"2\":0.5", new="\"3\":0.5"),
      native_answer_fixture_wire().replace(old="\"noul\":0.25", new="\"noul\":null"),
      native_answer_fixture_wire().replace(old="\"0\":0,", new=""),
      native_answer_fixture_wire().replace(old="\"0\":0,", new="\"0\":0,\"3\":0,"),
    ] {
    assert_true(project_native_decision_answers(original, provider, request,
      native_answer_fixture_source(wire), 10000, 1000, 40, 10000) is Err(Malformed))
  }
  assert_eq(calls(), 0)
  retire_native_decision_projection(cursor)
  retire_native_decision_request(original)
}

///|
test "native answer finite work and wire limits do not alter original raw or issue completion" {
  let (provider, request, calls) = native_decision_projection_fixture("null")
  let cursor = start_native_decision_projection(provider, request, 10000, 1000, 40, 100, 10000).unwrap()
  let original = native_projection_run(cursor, 1)
  let raw = native_answer_fixture_source(native_answer_fixture_wire())
  let (wire, work) = project_native_decision_answers(original, provider, request,
    raw, 10000, 1000, 40, 10000).unwrap()
  assert_eq(project_native_decision_answers(original, provider, request, raw,
    10000, 1000, 40, work).unwrap(), (wire, work))
  for (bytes, nodes, depth, budget) in [(1,1000,40,10000),(10000,1,40,10000),
    (10000,1000,1,10000),(10000,1000,40,work-1),(10000,1000,40,0)] {
    assert_true(project_native_decision_answers(original, provider, request,
      raw, bytes, nodes, depth, budget) is Err(Limit))
  }
  // Out-of-grid data can be mapped, but remains invalid under Common's
  // independent validator. The codec must not round it into a valid answer.
  let bad_raw = native_answer_fixture_source(native_answer_fixture_wire().replace(old="0.25", new="0.251"))
  let bad_wire = project_native_decision_answers(original, provider, request,
    bad_raw, 10000, 1000, 40, 10000).unwrap().0
  assert_true(@environment.validate_decision_answers(original.decision.unwrap(),
    native_answer_fixture_source(bad_wire), @environment.initial_jev_decision_profile(),
    10000) is Err(_))
  assert_true(native_decision_field(raw, "unknown") is Some(_))
  assert_eq(calls(), 0)
  retire_native_decision_projection(cursor)
  retire_native_decision_request(original)
}
