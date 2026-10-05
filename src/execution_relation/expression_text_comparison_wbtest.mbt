///|
fn borrowed_text_comparison(op : String) -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"left\":{\"type\":\"string\",\"nullable\":true},\"right\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":{\"" +
    op +
    "\":[{\"field\":\"left\"},{\"field\":\"right\"}]}}}]",
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
test "long expression comparison exposes charging and equal prefix scans" {
  let text = String::make(4096, 'g')
  let control = { remaining: 10000, max_frames: 10, }
  let workspace = row_workspace(10)
  let frame = expression_frame(
    borrowed_text_comparison("eq"),
    Map([("left", Text(text)), ("right", Text(text))]),
    [],
    control,
    workspace,
    None,
  ).unwrap()
  let mut result : EvaluatedValue? = None
  let mut polls = 0
  for _ in 0..<15000 {
    let before = control.remaining
    result = advance_expression_frame(frame).unwrap()
    assert_true(before - control.remaining <= 64)
    polls += 1
    if result is Some(_) {
      break
    }
  }
  guard result is Some(result) else { fail("comparison did not terminate") }
  assert_true(result.value is Boolean(true))
  assert_true(polls > 12000)
  assert_eq(control.remaining, 10000 - 8192 - 15)
  assert_eq(workspace.live, 0)
}

///|
test "long expression comparison keeps independent logical and workspace bounds" {
  // Three entries, two retained operands and two consumptions of Text weight
  // 257, then one Boolean result: 1032 work. Two quoted 258-byte roots peak
  // at 516 live bytes. Binary views copy zero entries: the continuation plus
  // ten measurement slots need eleven slots; comparison reserves two handles.
  for
    (work, live, slots, failure) in [
      (1032L, 516L, 11, 0),
      (1031L, 516L, 11, 1),
      (1032L, 515L, 11, 2),
      (1032L, 516L, 10, 3),
    ] {
    let logical = text_expression_budget(work, live)
    let workspace = row_workspace(slots)
    let text = Text(String::make(256, 'g'))
    let frame = expression_frame(
      borrowed_text_comparison("eq"),
      Map([("left", text), ("right", text)]),
      [],
      { remaining: 10000, max_frames: 10, },
      workspace,
      Some(expression_roots(logical, 10)),
    ).unwrap()
    let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
    for _ in 0..<2000 {
      result = advance_expression_frame(frame)
      if !(result is Ok(None)) {
        break
      }
    }
    match failure {
      0 => {
        guard result is Ok(Some(value)) else {
          fail("exact comparison boundary")
        }
        assert_true(value.value is Boolean(true))
        assert_eq(
          (logical.work, logical.peak, workspace.peak),
          (1032L, 516L, 11),
        )
        release_logical_root(logical, value.root.unwrap()).unwrap()
      }
      1 =>
        assert_true(
          result
          is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
        )
      2 =>
        assert_true(result is Err({ kind: LogicalValue(LiveValueLimit), .. }))
      3 => assert_true(result is Err({ kind: WorkspaceLimit, .. }))
      _ => fail("unknown boundary")
    }
    close_expression_frame(frame)
    assert_eq((logical.live, workspace.live), (0L, 0))
  }
}

///|
test "long comparison preserves exact control and UTF16 result rules" {
  // Six semantic transitions and the field names left/right (4+5 bytes) cost
  // fifteen units. Binary views copy zero entries; each operand adds 256.
  for control_limit in [527, 526] {
    let text = Text(String::make(256, 'g'))
    let control = { remaining: control_limit, max_frames: 10, }
    let workspace = row_workspace(2)
    let frame = expression_frame(
      borrowed_text_comparison("eq"),
      Map([("left", text), ("right", text)]),
      [],
      control,
      workspace,
      None,
    ).unwrap()
    let result = advance_expression_frame(frame, drain=true)
    if control_limit == 527 {
      assert_true(result is Ok(Some({ value: Boolean(true), .. })))
      assert_eq(control.remaining, 0)
      assert_eq(workspace.peak, 2)
    } else {
      assert_true(result is Err({ kind: ControlLimit, .. }))
    }
    assert_eq(workspace.live, 0)
  }
  let prefix = String::make(80, 'g')
  for
    (op, left, right, expected) in [
      ("eq", Text(prefix), Text(prefix), Boolean(true)),
      ("neq", Text(prefix), Text(prefix + "a"), Boolean(true)),
      ("is_distinct_from", Text(prefix), Text(prefix), Boolean(false)),
      ("is_distinct_from", Text(prefix), Null, Boolean(true)),
      ("lt", Text(prefix + "😀"), Text(prefix + "\u{e000}"), Boolean(true)),
      ("lte", Text(prefix), Text(prefix), Boolean(true)),
      ("gt", Text(prefix + "b"), Text(prefix + "a"), Boolean(true)),
      ("gte", Text(prefix), Text(prefix), Boolean(true)),
      ("lt", Text(prefix), Text(prefix + "a"), Boolean(true)),
      ("nullif", Text(prefix), Text(prefix), Null),
      ("nullif", Text(prefix), Text(prefix + "a"), Text(prefix)),
      ("nullif", Text(prefix), Null, Text(prefix)),
      ("eq", Text(prefix), Null, Null),
      ("eq", Null, Text(prefix), Null),
    ] {
    for drain in [false, true] {
      let workspace = row_workspace(2)
      let frame = expression_frame(
        borrowed_text_comparison(op),
        Map([("left", left), ("right", right)]),
        [],
        { remaining: 10000, max_frames: 10, },
        workspace,
        None,
      ).unwrap()
      let mut result : EvaluatedValue? = None
      for _ in 0..<1000 {
        result = advance_expression_frame(frame, drain~).unwrap()
        if result is Some(_) {
          break
        }
      }
      guard result is Some(result) else {
        fail("comparison vector did not terminate")
      }
      assert_eq(object_result_wire(result.value), object_result_wire(expected))
      assert_eq(workspace.live, 0)
    }
  }
}

///|
test "comparison reserves cursor custody before construction" {
  let text = Text(String::make(256, 'g'))
  let workspace = row_workspace(1)
  let frame = expression_frame(
    borrowed_text_comparison("eq"),
    Map([("left", text), ("right", text)]),
    [],
    { remaining: 10000, max_frames: 10, },
    workspace,
    None,
  ).unwrap()
  assert_true(
    advance_expression_frame(frame, drain=true)
    is Err({ kind: WorkspaceLimit, .. }),
  )
  assert_eq((workspace.peak, workspace.live), (1, 0))
  assert_true(frame.closed)
}

///|
test "pending comparison cleanup preserves borrowed roots and consumed work" {
  for phase in [0, 1, 2] {
    let logical = text_expression_budget(2000L, 1000L)
    let borrowed = retain_logical_value(logical, Number(7)).unwrap()
    let text = Text(String::make(256, 'g'))
    let workspace = row_workspace(20)
    let frame = expression_frame(
      borrowed_text_comparison("eq"),
      Map([("left", text), ("right", text)]),
      [],
      { remaining: 10000, max_frames: 10, },
      workspace,
      Some(expression_roots(logical, 10)),
    ).unwrap()
    let mut reached = false
    for _ in 0..<2000 {
      assert_true(advance_expression_frame(frame) is Ok(None))
      if frame.state is CompareBinary(state) &&
        state.phase == phase &&
        (if phase == 2 { state.offset > 64 } else { state.charge.offset > 64 }) {
        reached = true
        break
      }
    }
    assert_true(reached)
    assert_eq(logical.live, 517L)
    let consumed = logical.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq((logical.work, logical.live, workspace.live), (consumed, 1L, 0))
    assert_false(borrowed.released)
    assert_true(
      advance_expression_frame(frame) is Err({ kind: InvalidControlLimits, .. }),
    )
    release_logical_root(logical, borrowed).unwrap()
  }
}

///|
test "bounded filter stops within its demanded long Text comparison" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"tag\":\"" + String::make(256, 'g') + "\"}]",
    compare_text=true,
    fragment_rows=1L,
  )
  let logical = execution.state.logical.unwrap()
  let mut reached = false
  for _ in 0..<4000 {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(_, ..) =>
        fail("filter failed before pending comparison")
      _ => fail("filter completed before pending comparison")
    }
    if execution.state.predicate_execution is Some(frame) &&
      frame.state is CompareBinary(state) &&
      state.phase == 2 &&
      state.offset > 64 {
      reached = true
      break
    }
  }
  assert_true(reached)
  let consumed = logical.work
  let held = execution.state.workspace.live
  assert_false(execution.state.input_roots[0].root.released)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
  )
  assert_eq((logical.work, execution.state.workspace.live), (consumed, held))
  assert_true(execution.state.rows.val is None)
  assert_false(execution.accepted.val)
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_eq(
    (logical.work, logical.live, execution.state.workspace.live),
    (consumed, 0L, 0),
  )
  assert_true(producer_read_available(input))
}
