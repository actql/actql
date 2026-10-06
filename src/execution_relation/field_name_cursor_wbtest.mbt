///|
fn field_name_expression(name : String) -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"" +
    name +
    "\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"value\":{\"field\":\"" +
    name +
    "\"}}}]",
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
test "long field names never charge a whole spelling in one frame poll" {
  let name = "x".repeat(256)
  let control = { remaining: 1000, max_frames: 10, }
  let workspace = row_workspace(10)
  let frame = expression_frame(
    field_name_expression(name),
    Map([("x".repeat(255) + "y", Number(9)), (name, Number(7))]),
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
          assert_true(result.value is Number(7))
          complete = true
        }
      }
      assert_true(
        before - control.remaining <= 64,
        msg="a field lookup must not hide whole-Text work in one poll",
      )
    }
  }
  assert_true(complete)
  // Entry and Return transitions, plus 256 authored UTF-8 bytes.
  assert_eq(control.remaining, 742)
  assert_eq(workspace.live, 0)
}

///|
test "field name cursor preserves exact work workspace and NULL boundaries" {
  let name = "x".repeat(256)
  for quantum in [1, 7, 256] {
    for value in [Number(7), Null] {
      for (work, slots, expected) in [(2L, 2, 0), (1L, 2, 1), (2L, 1, 2)] {
        let logical = text_expression_budget(work, 10L)
        let workspace = row_workspace(slots)
        let frame = expression_frame(
          field_name_expression(name),
          Map([(name, value)]),
          [],
          { remaining: 258, max_frames: 10, },
          workspace,
          Some(expression_roots(logical, 10)),
        ).unwrap()
        let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
        for _ in 0..<400 {
          for _ in 0..<quantum {
            if result is Ok(None) {
              result = advance_expression_frame(frame)
            }
          }
        }
        match expected {
          0 => {
            guard result is Ok(Some(result)) else {
              fail("exact field bounds failed")
            }
            match (value, result.value) {
              (Number(7), Number(7)) | (Null, Null) => ()
              _ => fail("field binding changed its value")
            }
            assert_eq(logical.work, 2L)
            assert_eq(workspace.peak, 2)
            release_logical_root(logical, result.root.unwrap()).unwrap()
          }
          1 =>
            assert_true(
              result
              is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
            )
          _ => assert_true(result is Err({ kind: WorkspaceLimit, .. }))
        }
        assert_eq(logical.live, 0L)
        assert_eq(workspace.live, 0)
      }
    }
  }
}

///|
test "field name cursor keeps missing binding precedence and borrowed input on stop" {
  let name = "x".repeat(256)
  let expression = field_name_expression(name)
  for (limit, missing) in [(257, true), (256, false)] {
    let frame = expression_frame(
      expression,
      Map([("x".repeat(255) + "y", Number(9))]),
      [],
      { remaining: limit, max_frames: 10, },
      row_workspace(2),
      None,
    ).unwrap()
    let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
    for _ in 0..<400 {
      if result is Ok(None) {
        result = advance_expression_frame(frame)
      }
    }
    if missing {
      assert_true(result is Err({ kind: MissingValue, .. }))
    } else {
      assert_true(result is Err({ kind: ControlLimit, .. }))
    }
    assert_eq(frame.workspace.live, 0)
  }
  let logical = text_expression_budget(100L, 100L)
  let borrowed = retain_logical_value(logical, Number(7)).unwrap()
  let input = Map([(name, Number(7))])
  let workspace = row_workspace(2)
  let frame = expression_frame(
    expression,
    input,
    [],
    { remaining: 1000, max_frames: 10, },
    workspace,
    Some(expression_roots(logical, 10)),
  ).unwrap()
  let mut inside = false
  for _ in 0..<400 {
    if !inside {
      assert_true(advance_expression_frame(frame).unwrap() is None)
      inside = frame.state is FieldName(state) &&
        state.measured &&
        state.candidate is Some(_) &&
        state.offset == 64
    }
  }
  assert_true(inside)
  let work = logical.work
  close_expression_frame(frame)
  close_expression_frame(frame)
  assert_eq(logical.work, work)
  assert_eq(workspace.live, 0)
  assert_false(borrowed.released)
  assert_true(input.get(name) is Some(Number(7)))
  release_logical_root(logical, borrowed).unwrap()
  assert_eq(logical.live, 0L)
}

///|
test "Unicode field names preserve UTF8 charges and finite frame progress" {
  let name = "x".repeat(63) + "😀" + "é".repeat(65)
  // Two transitions + 197 raw UTF-8 bytes; no normalization or resume surcharge.
  for (limit, success) in [(199, true), (198, false)] {
    let control = { remaining: limit, max_frames: 10, }
    let frame = expression_frame(
      field_name_expression(name),
      Map([(name, Number(7))]),
      [],
      control,
      row_workspace(2),
      None,
    ).unwrap()
    let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
    for _ in 0..<400 {
      if result is Ok(None) {
        result = advance_expression_frame(frame)
      }
    }
    if success {
      assert_true(result is Ok(Some({ value: Number(7), .. })))
      assert_eq(control.remaining, 0)
    } else {
      assert_true(result is Err({ kind: ControlLimit, .. }))
    }
    assert_eq(frame.workspace.live, 0)
  }
}

///|
test "long prior-slot field names use the same cursor without reading input" {
  let name = "x".repeat(256)
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":[{\"" +
    name +
    "\":\"7\"},{\"zz\":{\"field\":\"" +
    name +
    "\"}}]}]",
  )
  let expression = @lower.lower_expression(owner, 1, 1, {
    max_nodes: 100,
    max_work: 10000,
    max_depth: 20,
    max_literal_nodes: 100,
    max_literal_text_bytes: 10000,
  }).unwrap()
  assert_true(
    @lower.expression_body(expression) is Field(_, @relation.PriorSlot(0)),
  )
  for (slots, success) in [([Null], true), ([], false)] {
    let frame = expression_frame(
      expression,
      Map([(name, Number(9))]),
      slots,
      { remaining: 258, max_frames: 10, },
      row_workspace(2),
      None,
    ).unwrap()
    let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
    for _ in 0..<400 {
      if result is Ok(None) {
        result = advance_expression_frame(frame)
      }
    }
    if success {
      assert_true(result is Ok(Some({ value: Null, .. })))
    } else {
      assert_true(result is Err({ kind: MissingValue, .. }))
    }
    assert_eq(frame.workspace.live, 0)
  }
}
