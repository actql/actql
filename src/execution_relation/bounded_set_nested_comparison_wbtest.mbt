///|
fn bounded_nested_set_fixture(
  operation? : String = "except",
  duplicates? : String = "all",
  max_entries? : Int = 1000,
) -> (@bounded.Control, BoundedSetExecution, Array[ProducerRead]) raise {
  let schema = "{\"id\":{\"type\":\"object\",\"nullable\":false," +
    "\"fields\":{\"p\":{\"type\":\"array\",\"nullable\":false," +
    "\"items\":{\"type\":\"string\",\"nullable\":true}}}}}"
  let row = fn(suffix : String) {
    "{\"id\":{\"p\":[\"" + String::make(256, 'g') + suffix + "\",null]}}"
  }
  let (control, started, inputs) = bounded_set_fixture(
    operation~,
    duplicates~,
    max_entries~,
    max_work=100000,
    left_schema=schema,
    right_schema=schema,
    left_rows="[" + row("a") + "," + row("a") + "," + row("b") + "]",
    right_rows="[" + row("a") + "]",
    max_rows=4,
  )
  (control, started.unwrap(), inputs)
}

///|
test "public Set fixture has a live Text scan at its cancellation work barrier" {
  let schema = "{\"items\":{\"type\":\"array\",\"nullable\":false," +
    "\"max_items\":2,\"items\":{\"type\":\"string\",\"nullable\":true}}," +
    "\"marker\":{\"type\":\"number\",\"nullable\":false}}"
  let row = fn(suffix : String, marker : Int) {
    "{\"items\":[\"" +
    String::make(256, 'g') +
    suffix +
    "\",null],\"marker\":" +
    marker.to_string() +
    "}"
  }
  let (control, started, inputs) = bounded_set_fixture(
    operation="except",
    duplicates="all",
    max_work=100000,
    left_schema=schema,
    right_schema=schema,
    left_rows="[" + row("a", 1) + "," + row("a", 1) + "," + row("b", 2) + "]",
    right_rows="[" + row("a", 1) + "," + row("a", 1) + "]",
    max_rows=4,
  )
  let execution = started.unwrap()
  // Eight Host quanta, not a sampled wall-clock delay. This exact fixture
  // has finished admission and is scanning the first private sort comparison.
  for quantum in 1..<9 {
    guard advance_bounded_set(execution, 256).unwrap()
      is BoundedSetContinue(progress~, work~) else {
      fail("public cancellation barrier must precede completion")
    }
    assert_eq(progress, 0L)
    assert_eq(work, quantum.to_int64() * 256L)
  }
  assert_true(execution.state.phase is SortLeft)
  guard execution.state.comparison.tree is Some(cursor) &&
    cursor.frames.last() is Some(TextUnits(_, _, text, _)) else {
    fail("public cancellation barrier must retain a Text comparison")
  }
  assert_eq(text.phase, 3)
  assert_true(text.offset > 0 && text.offset < 257)
  assert_true(execution.state.workspace.live > 0)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_set(execution, 1).unwrap()
    is BoundedSetStopped(@bounded.Cancelled, ..),
  )
  assert_true(cleanup_bounded_set(execution).unwrap())
  assert_false(cleanup_bounded_set(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
  assert_true(inputs.all(producer_read_available))
}

///|
test "set operation yields inside nested object array Text comparisons" {
  let (_, execution, inputs) = bounded_nested_set_fixture()
  let state = execution.state
  let mut output : CompletedOutput? = None
  for _ in 0..<20000 {
    let before = state.control.remaining
    let comparing = state.phase is (SortLeft | SortRight | Merge)
    let poll = advance_bounded_set(execution, 1).unwrap()
    if comparing {
      // The first comparison poll may also enter one logical merge action.
      // Subsequent recursive polls never charge that action again.
      assert_true(before - state.control.remaining <= 2)
    }
    match poll {
      BoundedSetContinue(..) => ()
      BoundedSetComplete(value, ..) => {
        output = Some(value)
        break
      }
      _ => fail("nested set did not complete")
    }
  }
  assert_true(output is Some(value) && completed_row_count(value) == 2)
  assert_true(cleanup_bounded_set(execution).unwrap())
  assert_true(inputs.all(producer_read_available))
}

///|
fn nested_set_texts(output : CompletedOutput) -> Array[String] raise {
  let result : Array[String] = []
  for row in 0..<completed_row_count(output) {
    guard completed_cell(output, row, 0)
      is Some(Captured(@admitted.Object(fields))) &&
      @admitted.element_at(fields, 0) is Some(("p", @admitted.Array(items))) &&
      @admitted.element_at(items, 0) is Some(@admitted.Text(text)) &&
      @admitted.element_at(items, 1) is Some(@admitted.Null) else {
      fail("unexpected nested survivor")
    }
    result.push(text)
  }
  result
}

///|
test "nested set preserves all variants and logical work across quanta" {
  for
    (operation, duplicates, suffixes) in [
      ("except", "all", ["a", "b"]),
      ("except", "distinct", ["b"]),
      ("intersect", "all", ["a"]),
      ("intersect", "distinct", ["a"]),
    ] {
    let mut prior : Int? = None
    for quantum in [1, 7] {
      let (_, execution, inputs) = bounded_nested_set_fixture(
        operation~,
        duplicates~,
      )
      let mut output : CompletedOutput? = None
      for _ in 0..<20000 {
        match advance_bounded_set(execution, quantum).unwrap() {
          BoundedSetContinue(..) => ()
          BoundedSetComplete(value, ..) => {
            output = Some(value)
            break
          }
          _ => fail("nested variant did not complete")
        }
      }
      guard output is Some(output) else {
        fail("nested variant did not terminate")
      }
      assert_eq(
        nested_set_texts(output),
        suffixes.map(suffix => String::make(256, 'g') + suffix),
      )
      assert_true(completed_output_matches_inputs(output, inputs))
      let spent = 100000 - execution.state.control.remaining
      if prior is Some(value) {
        assert_eq(spent, value)
      }
      prior = Some(spent)
      assert_true(cleanup_bounded_set(execution).unwrap())
      assert_false(cleanup_bounded_set(execution).unwrap())
      assert_eq(execution.state.workspace.live, 0)
      assert_true(execution.state.comparison.tree is None)
      assert_true(inputs.all(producer_read_available))
    }
  }
}

///|
test "nested comparison preserves independently calculated work and frame limits" {
  // Captured wrapper 1; Object node 1; two 'p' name bytes 2; Array node 1;
  // Text node 1 plus two 257-byte strings 514; NULL node 1 = 521.
  // The handle plus Object continuation, value and name frames peak at four.
  for
    (work, slots, frames, succeeds) in [
      (521, 4, 3, true),
      (520, 4, 3, false),
      (521, 3, 3, false),
      (521, 4, 2, false),
    ] {
    let (engine, execution, inputs) = bounded_nested_set_fixture()
    guard producer_read_cell(inputs[0], 0, 0) is Some(Captured(a)) &&
      producer_read_cell(inputs[0], 1, 0) is Some(Captured(b)) else {
      fail("missing admitted nested inputs")
    }
    let control : ControlBudget = { remaining: work, max_frames: frames, }
    let workspace = row_workspace(slots)
    let cursor = start_complete_tree_comparison(a, b, control, workspace).unwrap()
    let mut result : Result[Int?, OrderingIssue] = Ok(None)
    for _ in 0..<2000 {
      let before = control.remaining
      result = advance_complete_tree_comparison(cursor, control)
      assert_true(before - control.remaining <= 1)
      if !(result is Ok(None)) {
        break
      }
    }
    if succeeds {
      assert_true(result is Ok(Some(0)))
      assert_eq(control.remaining, 0)
      assert_eq(workspace.peak, 4)
      let reference : ControlBudget = { remaining: 521, max_frames: 3, }
      assert_true(
        compare_complete_value(Captured(a), Captured(b), reference) is Ok(0),
      )
      assert_eq(reference.remaining, 0)
    } else {
      assert_true(result is Err(Limit))
      assert_false(cursor.closed)
      assert_true(workspace.live > 0)
    }
    let remaining = control.remaining
    close_complete_tree_comparison(cursor)
    close_complete_tree_comparison(cursor)
    assert_eq(workspace.live, 0)
    assert_eq(control.remaining, remaining)
    assert_true(cursor.frames.is_empty())
    assert_true(
      advance_complete_tree_comparison(cursor, control) is Err(InvalidInput),
    )
    assert_true(@bounded.request_cancel(engine))
    assert_true(
      advance_bounded_set(execution, 1).unwrap()
      is BoundedSetStopped(@bounded.Cancelled, ..),
    )
    assert_true(cleanup_bounded_set(execution).unwrap())
    assert_true(inputs.all(producer_read_available))
  }
}

///|
test "complete tree cursor preserves admitted domains and canonical UTF-16 order" {
  let prefix = String::make(128, 'g')
  for
    (left, right, expected, work) in [
      ("[]", "[]", 0, 2),
      ("[0]", "[0]", 0, 3),
      ("[null]", "[]", 1, 2),
      ("[true]", "[false]", 1, 3),
      ("[1,2]", "[1,3]", -1, 4),
      ("{\"p\":null}", "{}", 1, 2),
      ("{\"a\":1}", "{\"b\":0}", -1, 4),
      (
        "{\"p\":[\"" + prefix + "\u{e000}\"]}",
        "{\"p\":[\"" + prefix + "\u{10000}\"]}",
        1,
        269,
      ),
    ] {
    // Preserve the historical structural-payload corpus and its exact charges.
    // Typed JSON marker charges have dedicated domain regressions.
    let contract = @contract.primitive(JsonType, nullable=false)
    let limits : @admitted.Limits = {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }
    let admitted_left = @admitted.admit(contract, input_cursor(left), limits).unwrap().value
    let admitted_right = @admitted.admit(contract, input_cursor(right), limits).unwrap().value
    guard admitted_left is @admitted.JsonData(a) &&
      admitted_right is @admitted.JsonData(b) else {
      fail("JSON admission must retain its domain marker")
    }
    let control : ControlBudget = { remaining: work, max_frames: 10, }
    let workspace = row_workspace(10)
    let cursor = start_complete_tree_comparison(a, b, control, workspace).unwrap()
    let mut actual : Int? = None
    for _ in 0..<2000 {
      let before = control.remaining
      match advance_complete_tree_comparison(cursor, control) {
        Ok(None) => ()
        Ok(Some(value)) => {
          actual = Some(value)
          break
        }
        Err(_) => fail("corpus rejected exact charge")
      }
      assert_true(before - control.remaining <= 1)
    }
    assert_eq(actual, Some(expected))
    assert_eq(control.remaining, 0)
    assert_eq(workspace.live, 0)
    let reference : ControlBudget = { remaining: work, max_frames: 10, }
    assert_true(
      compare_complete_value(Captured(a), Captured(b), reference) is Ok(value) &&
      value == expected,
    )
    assert_eq(reference.remaining, 0)
  }
}

///|
test "complete tree vector charges all dimensions before comparing one" {
  guard runtime_vector([1.0, 2.0, 3.0]) is Captured(a) &&
    runtime_vector([0.0, 2.0, 3.0]) is Captured(b) else {
    fail("missing vectors")
  }
  for work in [5, 4] {
    let control : ControlBudget = { remaining: work, max_frames: 1, }
    let workspace = row_workspace(2)
    let cursor = start_complete_tree_comparison(a, b, control, workspace).unwrap()
    let mut result : Result[Int?, OrderingIssue] = Ok(None)
    for _ in 0..<20 {
      let before = control.remaining
      result = advance_complete_tree_comparison(cursor, control)
      assert_true(before - control.remaining <= 1)
      if !(result is Ok(None)) {
        break
      }
    }
    if work == 5 {
      assert_true(result is Ok(Some(1)))
      assert_eq(control.remaining, 0)
    } else {
      assert_true(result is Err(Limit))
      assert_eq(control.remaining, 2)
    }
    close_complete_tree_comparison(cursor)
    assert_eq(workspace.live, 0)
  }
}

///|
test "nested set retains borrowed roots and frames until confirmed stop" {
  for (sort, phase) in [(true, 1), (true, 3), (false, 1), (false, 3)] {
    let (control, execution, inputs) = bounded_nested_set_fixture()
    let state = execution.state
    let mut reached = false
    for _ in 0..<20000 {
      assert_true(
        advance_bounded_set(execution, 1).unwrap() is BoundedSetContinue(..),
      )
      let phase_matches = if sort {
        state.phase is SortLeft
      } else {
        state.phase is Merge
      }
      if phase_matches &&
        state.comparison.tree is Some(tree) &&
        tree.frames.last() is Some(TextUnits(_, _, text, _)) &&
        text.phase == phase &&
        (if phase == 1 { text.charge.offset } else { text.offset }) > 64 {
        reached = true
        break
      }
    }
    assert_true(reached)
    let held = state.workspace.live
    let remaining = state.control.remaining
    assert_true(@bounded.request_cancel(control))
    assert_eq(state.workspace.live, held)
    assert_true(state.comparison.tree is Some(_))
    assert_true(
      advance_bounded_set(execution, 1).unwrap()
      is BoundedSetStopped(@bounded.Cancelled, ..),
    )
    assert_eq(
      (state.workspace.live, state.control.remaining),
      (held, remaining),
    )
    assert_true(state.comparison.tree is Some(_))
    assert_false(state.accepted.val)
    assert_true(state.rows.val is None)
    assert_true(inputs.all(producer_read_available))
    assert_true(cleanup_bounded_set(execution).unwrap())
    assert_false(cleanup_bounded_set(execution).unwrap())
    assert_true(state.comparison.tree is None)
    assert_eq(state.workspace.live, 0)
    assert_eq(state.control.remaining, remaining)
    assert_true(inputs.all(producer_read_available))
  }
}
