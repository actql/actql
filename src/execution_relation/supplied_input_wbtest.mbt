///|
fn input_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="supplied.json",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn input_owner() -> @lower.BoundPrepared {
  let seed = capture_values(capture_fixture(), 0, max_rows=2, {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 200,
  }).unwrap()
  let pipeline = @pipeline.check(
    input_cursor("[{\"select\":[\"s\",\"n\"]}]"),
    [("select_0", captured_schema(seed))],
    None,
    Some(input_cursor("\"select_0\"")),
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "supplied input admits exact checked schema independently of input object order" {
  let owner = input_owner()
  let supplied = [input_cursor("{\"s\":\"é\",\"n\":3}")]
  let rows = capture_input(owner, 0, supplied, max_rows=1, {
    max_nodes: 3,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 7,
  }).unwrap()
  assert_eq(captured_origin(rows), SuppliedInput(0))
  assert_true(physical_equal(captured_owner(rows), owner))
  assert_true(captured_cell(rows, 0, 0) is Some(@admitted.Number(3.0)))
  assert_true(captured_cell(rows, 0, 1) is Some(@admitted.Text("é")))
  assert_eq(captured_usage(rows), { nodes: 3, text_bytes: 4, work: 7, })
  supplied[0] = input_cursor("{\"s\":\"changed\",\"n\":100}")
  supplied.clear()
  assert_true(captured_cell(rows, 0, 1) is Some(@admitted.Text("é")))
}

///|
test "supplied input rejects malformed values without coercion or source normalization" {
  let owner = input_owner()
  let limits = {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 200,
  }
  for
    text in [
      "{\"s\":\"ok\",\"n\":null}", "{\"s\":\"ok\",\"n\":\"3\"}", "{\"s\":\"ok\"}",
      "{\"s\":\"ok\",\"n\":3,\"extra\":4}",
    ] {
    guard capture_input(owner, 0, [input_cursor(text)], max_rows=1, limits)
      is Err(InputValue(0, _)) else {
      fail("invalid data admitted: " + text)
    }
  }
  let good = input_cursor("{\"s\":\"ok\",\"n\":3}")
  let bad = input_cursor("{\"s\":\"ok\",\"n\":null}")
  guard capture_input(owner, 0, [good, bad], max_rows=2, limits)
    is Err(InputValue(1, _)) else {
    fail("partial result")
  }
  assert_true(capture_input(owner, 0, [good], max_rows=1, limits) is Ok(_))
  // Source parsing intentionally normalizes. Construct noncanonical supplied
  // data after that boundary to test capture, not source authoring semantics.
  let raw = @source.parse_json("{\"s\":\"ok\",\"n\":3}", {
    max_input_bytes: 1000,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  guard raw.value is @source.Object(fields) else { fail("object") }
  fields[0] = {
    ..fields[0],
    value: { ..fields[0].value, value: @source.String("e\u{0301}"), },
  }
  let noncanonical = @decode.admit(raw, {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 1000,
    max_total_string_bytes: 1000,
  }).unwrap()
  guard capture_input(owner, 0, [noncanonical], max_rows=1, limits)
    is Err(InputValue(0, @admitted.ValueIssue(@admitted.NonCanonicalText, ..))) else {
    fail("capture repaired noncanonical supplied data")
  }
}

///|
test "supplied budgets are cumulative and invalid input target is not a values index" {
  let owner = input_owner()
  let good = input_cursor("{\"n\":1,\"s\":\"é\"}")
  let limits = { max_nodes: 6, max_text_bytes: 8, max_depth: 2, max_work: 14, }
  assert_true(
    capture_input(owner, 0, [good, good], max_rows=2, limits) is Ok(_),
  )
  for
    cap in [
      { ..limits, max_nodes: 5, },
      { ..limits, max_text_bytes: 7, },
      { ..limits, max_work: 13, },
      { ..limits, max_depth: 1, },
    ] {
    assert_true(
      capture_input(owner, 0, [good, good], max_rows=2, cap) is Err(_),
    )
  }
  assert_true(
    capture_input(owner, 0, [good, good], max_rows=1, limits)
    is Err(CaptureLimit),
  )
  assert_true(
    capture_input(owner, 1, [], max_rows=0, limits) is Err(NotRelationInput),
  )
  assert_true(
    capture_input(capture_fixture(), 0, [], max_rows=0, limits)
    is Err(NotRelationInput),
  )
  assert_eq(
    captured_row_count(
      capture_input(owner, 0, [], max_rows=0, {
        max_nodes: 0,
        max_text_bytes: 0,
        max_depth: 0,
        max_work: 0,
      }).unwrap(),
    ),
    0,
  )
}
