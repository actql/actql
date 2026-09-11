///|
fn capture_fixture() -> @lower.BoundPrepared {
  bound_pipeline(
    "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false},\"s\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]},\"as\":\"v\"},{\"select\":[\"s\",\"n\"]}]",
  )
}

///|
test "values capture pins exact owner and charges row keys and UTF-8 across rows" {
  let owner = capture_fixture()
  let limits = { max_nodes: 6, max_text_bytes: 10, max_depth: 2, max_work: 16, }
  let rows = capture_values(owner, 0, max_rows=2, limits).unwrap()
  assert_true(physical_equal(captured_owner(rows), owner))
  assert_true(!physical_equal(captured_owner(rows), capture_fixture()))
  assert_eq(captured_node(rows), 0)
  assert_eq(captured_row_count(rows), 2)
  assert_eq(captured_usage(rows), { nodes: 6, text_bytes: 10, work: 16, })
  assert_true(captured_cell(rows, 0, 0) is Some(@admitted.Number(1.0)))
  assert_true(captured_cell(rows, 1, 1) is Some(@admitted.Text("😀")))
  assert_true(captured_cell(rows, -1, 0) is None)
  assert_true(captured_cell(rows, 0, 2) is None)
  for
    cap in [
      { ..limits, max_nodes: 5, },
      { ..limits, max_text_bytes: 9, },
      { ..limits, max_work: 15, },
      { ..limits, max_depth: 1, },
    ] {
    guard capture_values(owner, 0, max_rows=2, cap) is Err(e) else {
      fail("expected budget")
    }
    assert_eq(e, CaptureLimit)
  }
  guard capture_values(owner, 0, max_rows=1, limits) is Err(e) else {
    fail("row budget")
  }
  assert_eq(e, CaptureLimit)
  assert_true(capture_values(owner, 0, max_rows=2, limits) is Ok(_))
}

///|
test "capture rejects wrong node and limits without exposing partial rows" {
  let owner = capture_fixture()
  let limits = {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 200,
  }
  for index in [-1, 1, 2] {
    guard capture_values(owner, index, max_rows=10, limits) is Err(e) else {
      fail("not values")
    }
    assert_eq(e, NotValuesNode)
  }
  guard capture_values(owner, 0, max_rows=10, { ..limits, max_work: -1, })
    is Err(e) else {
    fail("invalid limit")
  }
  assert_eq(e, InvalidCaptureLimits)
}

///|
test "nested value measurement preserves opaque business data and counts repeated occurrences" {
  let expr = lowered("{\"literal\":{\"$param\":[\"é\",1]}}")
  guard @lower.expression_body(expr) is @lower.Literal(checked) else {
    fail("literal")
  }
  let limits = { max_nodes: 4, max_text_bytes: 8, max_depth: 3, max_work: 12, }
  let budget = value_budget(limits).unwrap()
  assert_true(measure(checked.value, 1, budget))
  assert_eq(budget.nodes, 4)
  assert_eq(budget.text, 8)
  assert_eq(budget.work, 12)
  assert_true(!measure(checked.value, 1, budget))
  for
    cap in [
      { ..limits, max_depth: 2, },
      { ..limits, max_nodes: 3, },
      { ..limits, max_text_bytes: 7, },
      { ..limits, max_work: 11, },
    ] {
    assert_true(!measure(checked.value, 1, value_budget(cap).unwrap()))
  }
  let twice = value_budget({
    ..limits,
    max_nodes: 8,
    max_text_bytes: 16,
    max_work: 24,
  }).unwrap()
  assert_true(measure(checked.value, 1, twice))
  assert_true(measure(checked.value, 1, twice))
  assert_eq(twice.nodes, 8)
  assert_true(measure(checked.value, 1, value_budget(limits).unwrap()))
  guard checked.value is @admitted.Object(fields) else { fail("object") }
  let copy = @admitted.elements(fields)
  copy.clear()
  assert_eq(@admitted.element_count(fields), 1)
  assert_true(measure(checked.value, 1, value_budget(limits).unwrap()))
}
