///|
fn complete_tree_json_literal(text : String) -> @admitted.Value {
  @admitted.admit_json_literal(text, {
    max_nodes: 100,
    max_depth: 20,
    max_text_bytes: 1000,
  }).unwrap().0.value
}

///|
fn assert_complete_tree_json_order(
  left : @admitted.Value,
  right : @admitted.Value,
  expected : Int,
  work : Int,
  slots : Int,
  frames : Int,
  quantum : Int,
) -> Unit raise {
  let control : ControlBudget = { remaining: work, max_frames: frames, }
  let workspace = row_workspace(slots)
  let cursor = start_complete_tree_comparison(left, right, control, workspace).unwrap()
  let mut result : Result[Int?, OrderingIssue] = Ok(None)
  for _ in 0..<1000 {
    for _ in 0..<quantum {
      let remaining = control.remaining
      result = advance_complete_tree_comparison(cursor, control)
      assert_true(remaining - control.remaining <= 1)
      if !(result is Ok(None)) {
        break
      }
    }
    if !(result is Ok(None)) {
      break
    }
  }
  guard result is Ok(Some(actual)) else { fail("comparison did not complete") }
  assert_eq(actual, expected)
  assert_eq(control.remaining, 0)
  assert_eq((workspace.live, workspace.peak), (0, slots))
  // The expected order and work above are independently authored. The existing
  // complete-value owner must agree on both; it does not supply expectations.
  let reference : ControlBudget = { remaining: work, max_frames: frames, }
  assert_true(
    compare_complete_value(Captured(left), Captured(right), reference)
    is Ok(value) &&
    value == expected,
  )
  assert_eq(reference.remaining, 0)
  close_complete_tree_comparison(cursor)
  close_complete_tree_comparison(cursor)
  assert_eq(workspace.live, 0)
}

///|
test "JSON complete tree comparison retains distinct payloads and exact work" {
  // Work includes the Captured entry, JsonData entry, each visited payload
  // node and both UTF-8 key strings. Replacing JsonData adds no stack frame.
  for
    (left, right, expected, work, slots, frames) in [
      ("1", "2", -1, 3, 2, 1),
      ("2", "1", 1, 3, 2, 1),
      ("null", "null", 0, 3, 2, 1),
      ("null", "false", -1, 3, 2, 1),
      ("false", "true", -1, 3, 2, 1),
      ("[1,2]", "[1,3]", -1, 5, 3, 2),
      ("{\"a\":[1,{\"b\":2}]}", "{\"a\":[1,{\"b\":3}]}", -1, 11, 6, 5),
      ("{\"a\":[1,{\"b\":2}]}", "{\"a\":[1,{\"b\":2}]}", 0, 11, 6, 5),
      ("{\"é\":1}", "{\"e\u{0301}\":1}", 1, 8, 4, 3),
      ("{\"$json\":null}", "{\"$json\":0}", -1, 14, 4, 3),
    ] {
    for quantum in [1, 64] {
      assert_complete_tree_json_order(
        complete_tree_json_literal(left),
        complete_tree_json_literal(right),
        expected,
        work,
        slots,
        frames,
        quantum,
      )
    }
  }
}

///|
test "JSON complete tree comparison descends through typed container members" {
  let json = @contract.primitive(JsonType, nullable=false)
  let array = @contract.array_contract(json, nullable=false).unwrap()
  let object = @contract.object_contract(
    [("j", json)],
    nullable=false,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let limits : @admitted.Limits = {
    max_nodes: 100,
    max_depth: 20,
    max_text_bytes: 1000,
  }
  // Array: Captured + Array + JsonData + Number = four.
  // Object: Captured + Object + two key bytes + JsonData + Number = six.
  for
    (contract, left, right, work, slots, frames) in [
      (array, "[1]", "[2]", 4, 3, 2),
      (object, "{\"j\":1}", "{\"j\":2}", 6, 4, 3),
    ] {
    for quantum in [1, 64] {
      assert_complete_tree_json_order(
        @admitted.admit(contract, input_cursor(left), limits).unwrap().value,
        @admitted.admit(contract, input_cursor(right), limits).unwrap().value,
        -1,
        work,
        slots,
        frames,
        quantum,
      )
    }
  }
}

///|
test "JSON complete tree comparison preserves SQL NULL and scalar domains" {
  let json_null = complete_tree_json_literal("null")
  let json_one = complete_tree_json_literal("1")
  let json_text = complete_tree_json_literal("\"x\"")
  let limits : @admitted.Limits = {
    max_nodes: 100,
    max_depth: 20,
    max_text_bytes: 1000,
  }
  let sql_null = @admitted.admit(
      @contract.primitive(NumberType, nullable=true),
      input_cursor("null"),
      limits,
    ).unwrap().value
  let number = @admitted.admit(
      @contract.primitive(NumberType, nullable=false),
      input_cursor("1"),
      limits,
    ).unwrap().value
  let text = @admitted.admit(
      @contract.primitive(StringType, nullable=false),
      input_cursor("\"x\""),
      limits,
    ).unwrap().value
  for
    (left, right, expected) in [
      (sql_null, json_null, -1),
      (json_null, sql_null, 1),
      (number, json_one, -1),
      (text, json_text, -1),
    ] {
    assert_complete_tree_json_order(left, right, expected, 2, 2, 1, 1)
  }
  assert_true(unary(@lower.IsNull, capture(json_null)) is Ok(Boolean(false)))
  assert_true(unary(@lower.IsNull, capture(sql_null)) is Ok(Boolean(true)))
  let control : ControlBudget = { remaining: 1, max_frames: 1, }
  assert_true(
    compare_complete_value(capture(sql_null), capture(json_null), control)
    is Ok(-1),
  )
  assert_eq(control.remaining, 0)
}

///|
test "JSON complete tree comparison keeps exact limits and releases its frames" {
  let left = complete_tree_json_literal("1")
  let right = complete_tree_json_literal("2")
  // Both entries and the numeric payload require exactly three work units.
  for work in [3, 2] {
    let control : ControlBudget = { remaining: work, max_frames: 1, }
    let workspace = row_workspace(2)
    let cursor = start_complete_tree_comparison(left, right, control, workspace).unwrap()
    let mut result : Result[Int?, OrderingIssue] = Ok(None)
    for _ in 0..<10 {
      result = advance_complete_tree_comparison(cursor, control)
      if !(result is Ok(None)) {
        break
      }
    }
    if work == 3 {
      assert_true(result is Ok(Some(-1)))
      assert_eq(workspace.live, 0)
    } else {
      assert_true(result is Err(Limit))
      assert_eq(workspace.live, 2)
    }
    assert_eq(control.remaining, 0)
    close_complete_tree_comparison(cursor)
    close_complete_tree_comparison(cursor)
    assert_eq((control.remaining, workspace.live), (0, 0))
  }
  for (slots, frames) in [(1, 1), (2, 0)] {
    let control : ControlBudget = { remaining: 3, max_frames: frames, }
    let workspace = row_workspace(slots)
    assert_true(
      start_complete_tree_comparison(left, right, control, workspace)
      is Err(Limit),
    )
    assert_eq((control.remaining, workspace.live), (3, 0))
  }
}

///|
test "JSON complete tree comparison closes between marker and payload" {
  let left = complete_tree_json_literal("{\"a\":[1]}")
  let right = complete_tree_json_literal("{\"a\":[2]}")
  let control : ControlBudget = { remaining: 20, max_frames: 10, }
  let workspace = row_workspace(10)
  // Keep an unrelated owner's reservation live across comparison cleanup.
  assert_true(reserve_slots(workspace, 1))
  let cursor = start_complete_tree_comparison(left, right, control, workspace).unwrap()
  assert_true(advance_complete_tree_comparison(cursor, control) is Ok(None))
  assert_true(advance_complete_tree_comparison(cursor, control) is Ok(None))
  assert_true(
    cursor.frames[0]
    is CompareAdmitted(@admitted.Object(_), @admitted.Object(_)),
  )
  assert_eq((control.remaining, workspace.live, workspace.peak), (18, 3, 3))
  close_complete_tree_comparison(cursor)
  close_complete_tree_comparison(cursor)
  assert_eq((control.remaining, workspace.live), (18, 1))
  assert_true(
    advance_complete_tree_comparison(cursor, control) is Err(InvalidInput),
  )
  release_slots(workspace, 1)
  assert_eq(workspace.live, 0)
}
