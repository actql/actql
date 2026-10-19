///|
test "fixed interval arithmetic preserves exact full int64 amounts and nanoseconds" {
  for (source, expected) in [
    ("timestamp_add(CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP),'9007199254740993','ns')", "1970-04-15T05:59:59.254740993Z"),
    ("timestamp_sub(CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP),'1','ns')", "1969-12-31T23:59:59.999999999Z"),
    ("timestamp_sub(CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP),'-9223372036854775808','ns')", "2262-04-11T23:47:16.854775808Z"),
    ("timestamp_add(CAST('2026-10-19T00:00:00.000Z' AS TIMESTAMP),'1','d')", "2026-10-20T00:00:00.000Z"),
  ] {
    assert_true(run_expr("\"" + source + "\"") is Ok(Captured(@admitted.Timestamp(actual))) && actual == expected, msg=source)
  }
}

///|
test "fixed interval typed domain strict children and calendar range remain exact" {
  for source in [
    "timestamp_add(CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP),1,'s')",
    "timestamp_add(CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP),'9223372036854775808','ns')",
    "timestamp_add(CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP),'01','ns')",
  ] {
    assert_true(@pipeline.check(
      input_cursor("[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"derive\":{\"v\":\"" + source + "\"}}]"),
      [], None, None,
      { max_steps: 10, max_work: 100000, max_text_bytes: 10000, max_nodes: 1000, max_tokens: 1000, max_depth: 100, },
    ) is Err(_))
  }
}

///|
test "fixed interval int64 fields retain exact admitted values and original null failure order" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"stamp\":{\"type\":\"timestamp\",\"nullable\":true},\"amount\":{\"type\":\"int64\",\"nullable\":true}},\"rows\":[{\"stamp\":\"1970-01-01T00:00:00.000Z\",\"amount\":\"9007199254740993\"}]},\"as\":\"seed\"},{\"derive\":{\"shifted\":{\"timestamp_add\":[{\"field\":\"stamp\"},{\"field\":\"amount\"},{\"literal\":\"ns\"}]}}}]",
  )
  let result = evaluate_rows(row_kernel(owner, 1), row_capture(owner), 10,
    { remaining: 10000, max_frames: 100, }, row_output()).unwrap()
  assert_true(result.rows[0][2] is Captured(@admitted.Timestamp("1970-04-15T05:59:59.254740993Z")))
  let expression = lowered("\"timestamp_add(NULL,'1','s')\"")
  assert_true(evaluate_expression(expression, {}, [], { remaining: 10000, max_frames: 100, }) is Ok(Null))
  assert_true(run_expr("\"if(false,timestamp_add(CAST('9999-12-31T23:59:59.999999999Z' AS TIMESTAMP),'1','ns'),NULL)\"") is Ok(Null))
  assert_true(run_expr("\"timestamp_add(CAST('9999-12-31T23:59:59.999999999Z' AS TIMESTAMP),'1','ns')\"") is Err({ kind: Scalar(ArithmeticFailure), .. }))
  assert_true(run_expr("\"timestamp_add(if(1/0 > 0,NULL,CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP)),'1','s')\"") is Err(_))
}

///|
test "fixed interval Parameter binding keeps full exact identity and machine emission" {
  let declarations = @parameter.read_declarations(
    Some(input_cursor("{\"amount\":{\"type\":\"int64\",\"nullable\":false}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let checked = @pipeline.check(input_cursor(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"derive\":{\"shifted\":{\"timestamp_add\":[{\"cast\":{\"value\":{\"literal\":\"1970-01-01T00:00:00.000Z\"},\"target\":{\"type\":\"timestamp\"}}},{\"$param\":\"amount\"},{\"literal\":\"ns\"}]}}}]"),
    [], Some(declarations), None,
    { max_steps: 10, max_work: 100000, max_text_bytes: 10000, max_nodes: 1000, max_tokens: 1000, max_depth: 100, },
  ).unwrap()
  let prepared = @lower.prepare(checked, {
    max_nodes: 100, max_references: 100, max_work: 10000, max_identifier_bytes: 1000,
  }).unwrap()
  let mut prior : @parameter.BoundValues? = None
  for (amount, expected) in [
    ("9007199254740992", "1970-04-15T05:59:59.254740992Z"),
    ("9007199254740993", "1970-04-15T05:59:59.254740993Z"),
  ] {
    guard @parameter.bind(declarations, Some(input_cursor("{\"amount\":\"" + amount + "\"}")),
      { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, }).unwrap() is @parameter.Ready(values) else { fail("exact int64 binding") }
    if prior is Some(old) { assert_false(physical_equal(old, values)) }
    prior = Some(values)
    let owner = @lower.bind_parameters(prepared, Some(values), max_parameters=1, max_name_bytes=6).unwrap()
    let expr = @lower.lower_expression(owner, 1, 0, {
      max_nodes: 100, max_work: 10000, max_depth: 100, max_literal_nodes: 100, max_literal_text_bytes: 1000,
    }).unwrap()
    assert_true(evaluate_expression(expr, {}, [], { remaining: 10000, max_frames: 100, }) is Ok(Captured(@admitted.Timestamp(actual))) && actual == expected)
    let writer = @encode.writer(10000, 1000, 100)
    @lower.emit_expression(expr, writer)
    let wire = @encode.finish(writer)
    assert_true(wire.contains("\"body\":\"" + amount + "\""))
  }
}

///|
test "fixed interval normalized source re-admits without decimal or Number reinterpretation" {
  let original = "{\"timestamp_add\":[{\"cast\":{\"value\":{\"literal\":\"1970-01-01T00:00:00.000Z\"},\"target\":{\"type\":\"timestamp\"}}},{\"literal\":\"9007199254740993\"},{\"literal\":\"ns\"}]}"
  let first = lowered(original)
  let writer = @encode.writer(10000, 1000, 100)
  @lower.emit_expression_source(first, writer)
  let saved = @encode.finish(writer)
  assert_eq(saved, original)
  let restored = lowered(saved)
  let first_writer = @encode.writer(10000, 1000, 100)
  let restored_writer = @encode.writer(10000, 1000, 100)
  @lower.emit_expression(first, first_writer)
  @lower.emit_expression(restored, restored_writer)
  assert_eq(@encode.finish(first_writer), @encode.finish(restored_writer))
  assert_true(evaluate_expression(restored, {}, [], { remaining: 10000, max_frames: 100, })
    is Ok(Captured(@admitted.Timestamp("1970-04-15T05:59:59.254740993Z"))))
}
