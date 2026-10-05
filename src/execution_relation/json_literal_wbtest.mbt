///|
test "JSON null is captured data rather than SQL NULL in ordinary evaluation" {
  for source in ["null", "true", "1", "\"x\"", "[null]", "{\"k\":1}"] {
    let value = @admitted.admit_json_literal(source, {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      }).unwrap().0
    let captured = capture(value.value)
    assert_true(captured is Captured(_), msg=source)
    assert_true(
      unary(@lower.IsNull, captured) is Ok(Boolean(false)),
      msg=source,
    )
    assert_true(
      unary(@lower.NotNull, captured) is Ok(Boolean(true)),
      msg=source,
    )
    assert_true(
      unary(@lower.Negate, captured) is Err(InvalidOperand),
      msg=source,
    )
  }
  assert_true(unary(@lower.IsNull, Null) is Ok(Boolean(true)))
}

///|
test "typed JSON literal survives the ordinary expression evaluator" {
  for
    (body, expected) in [
      ("null", "{\"$json\":null}"),
      ("false", "{\"$json\":false}"),
      ("1.5", "{\"$json\":1.5}"),
      ("\"x\"", "{\"$json\":\"x\"}"),
      ("[null,1]", "{\"$json\":[null,1]}"),
      ("{\"k\":null}", "{\"$json\":{\"k\":null}}"),
    ] {
    let source = @encode.writer(1000, 1, 0)
    @encode.string_value(source, body)
    let expr = lowered(
      "{\"typed_literal\":{\"type\":\"json\",\"value\":" +
      @encode.finish(source) +
      "}}",
    )
    let value = evaluate_expression(expr, Map([]), [], {
      remaining: 1000,
      max_frames: 10,
    }).unwrap()
    guard value is Captured(value) else { fail("JSON domain was lost") }
    let writer = @encode.writer(1000, 100, 10)
    @admitted.emit_wire_value(value, writer)
    assert_eq(@encode.finish(writer), expected)
  }
  let json_null = lowered(
    "{\"is_null\":{\"typed_literal\":{\"type\":\"json\",\"value\":\"null\"}}}",
  )
  assert_true(
    evaluate_expression(json_null, Map([]), [], {
      remaining: 1000,
      max_frames: 10,
    }).unwrap()
    is Boolean(false),
  )
  let sql_null = lowered(
    "{\"is_null\":{\"cast\":{\"value\":{\"literal\":null},\"target\":{\"type\":\"number\"}}}}",
  )
  assert_true(
    evaluate_expression(sql_null, Map([]), [], {
      remaining: 1000,
      max_frames: 10,
    }).unwrap()
    is Boolean(true),
  )
}
