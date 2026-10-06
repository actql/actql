///|
test "JSON logical budgets count the payload once and wire keeps its envelope" {
  let value = logical_literal("[1,2]")
  guard value is Captured(checked) && checked is @admitted.JsonData(_) else {
    fail("expected a checked JSON domain")
  }
  // Logical array + two numbers cost three units. Physical typed wire is
  // {"$json":[1,2]}: 15 bytes, four nodes and depth two.
  let measured = measure_logical_value(value, 3L, 15, 4, 2).unwrap()
  assert_eq((measured.weight, measured.wire_bytes), (3L, 15))
  assert_true(
    measure_logical_value(value, 2L, 15, 4, 2) is Err(LogicalWorkLimit),
  )
  for limit in [3, 2] {
    let limits : ValueLimits = {
      max_nodes: 3,
      max_text_bytes: 0,
      max_depth: 3,
      max_work: limit,
    }
    let direct = value_budget(limits).unwrap()
    assert_eq(measure(checked, 2, direct), limit == 3)
    assert_eq((direct.work, direct.nodes, direct.text), (limit, limit, 0))
    let stepped = value_budget(limits).unwrap()
    let workspace = row_workspace(3)
    let cursor = start_stepped_measure_result(value, workspace).unwrap()
    let mut done = false
    let mut refused = false
    for _ in 0..<20 {
      if !done && !refused {
        match advance_stepped_measure_result(cursor, stepped) {
          SteppedMeasureContinue => ()
          SteppedMeasureComplete => done = true
          SteppedMeasureLimit => refused = true
          SteppedMeasureWorkspaceLimit => fail("unexpected workspace refusal")
        }
      }
    }
    assert_eq((done, refused), (limit == 3, limit == 2))
    assert_eq((stepped.work, stepped.nodes, stepped.text), (limit, limit, 0))
    clear_stepped_measure(cursor)
    clear_stepped_measure(cursor)
    assert_eq(workspace.live, 0)
  }
}
