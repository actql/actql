///|
fn raw_text_object_expression() -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"value\":{\"object\":{\"p\":{\"field\":\"payload\"}}}}}]",
  )
  @lower.lower_expression(owner, 1, 0, {
    max_nodes: 100,
    max_work: 10000,
    max_depth: 20,
    max_literal_nodes: 100,
    max_literal_text_bytes: 10000,
  }).unwrap()
}

///|
test "raw Text Object children never charge a complete long value in one poll" {
  let text = "x".repeat(256)
  let control = { remaining: 1000, max_frames: 10, }
  let workspace = row_workspace(20)
  let frame = expression_frame(
    raw_text_object_expression(),
    Map([("payload", Text(text))]),
    [],
    control,
    workspace,
    None,
  ).unwrap()
  let mut complete = false
  for _ in 0..<1000 {
    if !complete {
      let before = control.remaining
      match advance_expression_frame(frame).unwrap() {
        None => ()
        Some(result) => {
          assert_eq(
            object_result_wire(result.value),
            "{\"p\":\"" + text + "\"}",
          )
          complete = true
        }
      }
      assert_true(
        before - control.remaining <= 64,
        msg="raw Text admission must not hide a complete scan in one poll",
      )
    }
  }
  assert_true(complete)
  assert_eq(control.remaining, 729)
  assert_eq(workspace.live, 0)
}

///|
test "raw Text Object children retain independent work live and workspace bounds" {
  let text = "x".repeat(256)
  // Entries 2, Text produced/consumed 257 each, Object weight 259: 775.
  // Object wire 264 coexists with child wire 258: peak 522. The existing
  // Text measurement's ten handles plus three Object handles peak at 13.
  for quantum in [1, 7, 256] {
    for
      (work, live, slots, expected) in [
        (775L, 522L, 13, 0),
        (774L, 522L, 13, 1),
        (775L, 521L, 13, 2),
        (775L, 522L, 12, 3),
      ] {
      let logical = text_expression_budget(work, live)
      let workspace = row_workspace(slots)
      let frame = expression_frame(
        raw_text_object_expression(),
        Map([("payload", Text(text))]),
        [],
        { remaining: 10000, max_frames: 10, },
        workspace,
        Some(expression_roots(logical, 10)),
      ).unwrap()
      let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
      for _ in 0..<2000 {
        for _ in 0..<quantum {
          if result is Ok(None) {
            result = advance_expression_frame(frame)
          }
        }
      }
      match expected {
        0 => {
          guard result is Ok(Some(result)) else {
            fail("exact raw Text bounds")
          }
          assert_eq(
            object_result_wire(result.value),
            "{\"p\":\"" + text + "\"}",
          )
          assert_eq(
            (logical.work, logical.peak, workspace.peak),
            (775L, 522L, 13),
          )
          release_logical_root(logical, result.root.unwrap()).unwrap()
        }
        1 =>
          assert_true(
            result
            is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
          )
        2 =>
          assert_true(result is Err({ kind: LogicalValue(LiveValueLimit), .. }))
        _ => assert_true(result is Err({ kind: WorkspaceLimit, .. }))
      }
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}

///|
test "raw Text Object validation and charge cancellation keep borrowed roots" {
  let text = "x".repeat(256)
  for charging in [false, true] {
    let logical = text_expression_budget(10000L, 10000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(20)
    let frame = expression_frame(
      raw_text_object_expression(),
      Map([("payload", Text(text))]),
      [],
      { remaining: 10000, max_frames: 10, },
      workspace,
      Some(expression_roots(logical, 10)),
    ).unwrap()
    let mut inside = false
    let mut validation_polls = 0
    for _ in 0..<2000 {
      if !inside {
        assert_true(advance_expression_frame(frame).unwrap() is None)
        if frame.state is ObjectText(_, state) {
          if !state.checked {
            validation_polls += 1
          }
          inside = if charging {
            state.checked && state.remaining == 128
          } else {
            validation_polls == 3 && !state.checked
          }
        }
      }
    }
    assert_true(inside)
    // Caller root 1, two entries and produced/consumed Text 257 each.
    assert_eq((logical.work, logical.live), (517L, 523L))
    assert_true(frame.current_root is Some(_))
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq((logical.work, logical.live, workspace.live), (517L, 1L, 0))
    assert_false(borrowed.released)
    release_logical_root(logical, borrowed).unwrap()
    assert_eq(logical.live, 0L)
  }
}

///|
test "shared raw Text admission preserves data Unicode and exact byte charge" {
  let text = "x".repeat(63) + "😀" + "e\u{0301}\r\n"
  // 63 ASCII + supplementary 4 + NFD 3 + CR/LF 2: 72 UTF-8 bytes.
  for (limit, success) in [(72, true), (71, false)] {
    let workspace = row_workspace(3)
    let control = { remaining: limit, max_frames: 0, }
    let state = start_raw_text_admission(text, workspace).unwrap()
    let mut result : Result[@admitted.Value?, RowIssue] = Ok(None)
    for _ in 0..<200 {
      if result is Ok(None) {
        let before = control.remaining
        result = advance_raw_text_admission(state, control)
        assert_true(before - control.remaining <= 1)
      }
    }
    if success {
      assert_true(result is Ok(Some(@admitted.Text(actual))) && actual == text)
    } else {
      assert_true(result is Err(RowLimit))
    }
    assert_eq((control.remaining, workspace.live), (0, 0))
  }
  let malformed = "x".repeat(64) +
    String::from_array([(0xd800).unsafe_to_char()])
  let workspace = row_workspace(3)
  let state = start_raw_text_admission(malformed, workspace).unwrap()
  let control = { remaining: 100, max_frames: 0, }
  let mut result : Result[@admitted.Value?, RowIssue] = Ok(None)
  for _ in 0..<20 {
    if result is Ok(None) {
      result = advance_raw_text_admission(state, control)
    }
  }
  assert_true(result is Err(RowLimit))
  assert_eq(workspace.live, 0)
  assert_true(start_raw_text_admission(text, row_workspace(2)) is Err(RowLimit))
}

///|
test "array Text admission has exact limits transfer and stopped cleanup" {
  let text = "x".repeat(256)
  // Empty output still needs its temporary builder, but spends no item work.
  for slots in [0, 1] {
    let workspace = row_workspace(slots)
    let control = { remaining: 0, max_frames: 0, }
    let state = start_aggregate_array([], control, workspace)
    let mut result : Result[Value?, RowIssue] = Ok(None)
    for _ in 0..<4 {
      if result is Ok(None) {
        result = advance_aggregate_array(state)
      }
    }
    if slots == 1 {
      guard result is Ok(Some(value)) else { fail("empty Array builder") }
      assert_eq(object_result_wire(value), "[]")
    } else {
      assert_true(result is Err(RowLimit))
    }
    assert_eq((control.remaining, workspace.live), (0, 0))
  }
  // One item + 256 bytes; item/builder two slots + three Text handles.
  for (work, slots, expected) in [(257, 5, 0), (256, 5, 1), (257, 4, 2)] {
    let workspace = row_workspace(slots)
    let control = { remaining: work, max_frames: 0, }
    let state = start_aggregate_array([Text(text)], control, workspace)
    let mut result : Result[Value?, RowIssue] = Ok(None)
    for _ in 0..<1000 {
      if result is Ok(None) {
        result = advance_aggregate_array(state)
      }
    }
    if expected == 0 {
      guard result is Ok(Some(value)) else { fail("exact array Text bounds") }
      assert_eq(object_result_wire(value), "[\"" + text + "\"]")
      assert_eq((control.remaining, workspace.peak, workspace.live), (0, 5, 1))
      close_aggregate_array(state)
      assert_eq(workspace.live, 1)
      release_slots(workspace, 1)
    } else {
      assert_true(result is Err(RowLimit))
      assert_eq(workspace.live, 0)
    }
    assert_eq(workspace.live, 0)
  }
  for charging in [false, true] {
    let workspace = row_workspace(5)
    let control = { remaining: 1000, max_frames: 0, }
    let values = [Text(text)]
    let state = start_aggregate_array(values, control, workspace)
    let mut inside = false
    let mut validation_polls = 0
    for _ in 0..<1000 {
      if !inside {
        assert_true(advance_aggregate_array(state).unwrap() is None)
        if state.text is Some(admission) {
          if !admission.checked {
            validation_polls += 1
          }
          inside = if charging {
            admission.checked && admission.remaining == 128
          } else {
            validation_polls == 3 && !admission.checked
          }
        }
      }
    }
    assert_true(inside)
    let spent = control.remaining
    close_aggregate_array(state)
    close_aggregate_array(state)
    assert_eq((control.remaining, workspace.live), (spent, 0))
    assert_true(state.builder is None && state.text is None)
    assert_true(values[0] is Text(actual) && actual == text)
    assert_true(advance_aggregate_array(state) is Err(InvalidRows))
  }
}
