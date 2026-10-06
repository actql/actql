///|
fn property_name_expression(name : String) -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"" +
    name +
    "\":{\"type\":\"number\",\"nullable\":false}}}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"value\":{\"property\":{\"value\":{\"field\":\"payload\"},\"name\":\"" +
    name +
    "\"}}}}]",
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
test "property name cursor retains exact successful accounting and root bounds" {
  let name = "x".repeat(256)
  let value = capture(
    @admitted.object_value([(name, @admitted.number_value(7).unwrap())]).unwrap(),
  )
  // Two entries, twice Object weight 1+256+1, and Number result: 519.
  // Object wire is name bytes + braces/quotes/colon/number: 262. Nine
  // measure slots, the continuation and two name handles peak at twelve.
  for
    (work, live, slots, expected) in [
      (519L, 262L, 12, 0),
      (518L, 262L, 12, 1),
      (519L, 261L, 12, 2),
      (519L, 262L, 11, 3),
    ] {
    let logical = text_expression_budget(work, live)
    let workspace = row_workspace(slots)
    let control = { remaining: 10000, max_frames: 10, }
    let frame = expression_frame(
      property_name_expression(name),
      Map([("payload", value)]),
      [],
      control,
      workspace,
      Some(expression_roots(logical, 10)),
    ).unwrap()
    let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
    for _ in 0..<1000 {
      if result is Ok(None) {
        result = advance_expression_frame(frame)
      }
    }
    match expected {
      0 => {
        guard result is Ok(Some(result)) else {
          fail("exact property bounds failed")
        }
        assert_true(result.value is Number(7))
        assert_eq(
          (logical.work, logical.peak, workspace.peak),
          (519L, 262L, 12),
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
    assert_eq(logical.live, 0L)
    assert_eq(workspace.live, 0)
  }
}

///|
test "property name cursor preserves NULL refusal precedence and stop custody" {
  let name = "x".repeat(256)
  let expression = property_name_expression(name)
  for
    value in [
      Null,
      capture(
        @admitted.object_value([
          ("x".repeat(255) + "y", @admitted.number_value(7).unwrap()),
        ]).unwrap(),
      ),
    ] {
    for (limit, success) in [(267, true), (266, false), (265, false)] {
      let frame = expression_frame(
        expression,
        Map([("payload", value)]),
        [],
        { remaining: limit, max_frames: 10, },
        row_workspace(20),
        None,
      ).unwrap()
      let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
      for _ in 0..<400 {
        if result is Ok(None) {
          result = advance_expression_frame(frame)
        }
      }
      if value is Null && success {
        assert_true(result is Ok(Some({ value: Null, .. })))
      } else if value is Null {
        assert_true(result is Err({ kind: ControlLimit, .. }))
      } else if limit == 265 {
        assert_true(result is Err({ kind: ControlLimit, .. }))
      } else {
        assert_true(result is Err({ kind: MissingValue, .. }))
      }
    }
  }
  let value = capture(
    @admitted.object_value([(name, @admitted.number_value(7).unwrap())]).unwrap(),
  )
  let logical = text_expression_budget(10000L, 10000L)
  let workspace = row_workspace(20)
  let frame = expression_frame(
    expression,
    Map([("payload", value)]),
    [],
    { remaining: 1000, max_frames: 10, },
    workspace,
    Some(expression_roots(logical, 10)),
  ).unwrap()
  let mut inside = false
  for _ in 0..<1000 {
    if !inside {
      assert_true(advance_expression_frame(frame).unwrap() is None)
      inside = frame.state is PropertyName(state) &&
        !state.measured &&
        state.offset == 64
    }
  }
  assert_true(inside)
  assert_eq(logical.work, 518L)
  assert_eq(logical.live, 262L)
  close_expression_frame(frame)
  close_expression_frame(frame)
  assert_eq(logical.work, 518L)
  assert_eq(logical.live, 0L)
  assert_eq(workspace.live, 0)
}

///|
test "Unicode property name scanning is invariant across frame batching" {
  let name = "x".repeat(63) + "😀" + "é".repeat(65)
  let value = capture(
    @admitted.object_value([(name, @admitted.number_value(7).unwrap())]).unwrap(),
  )
  for quantum in [1, 7, 256] {
    let budget = { remaining: 208, max_frames: 10, }
    let frame = expression_frame(
      property_name_expression(name),
      Map([("payload", value)]),
      [],
      budget,
      row_workspace(3),
      None,
    ).unwrap()
    let mut complete = false
    for _ in 0..<400 {
      for _ in 0..<quantum {
        if !complete {
          match advance_expression_frame(frame).unwrap() {
            None => ()
            Some(value) => {
              assert_true(value.value is Number(7))
              complete = true
            }
          }
        }
      }
    }
    assert_true(complete)
    // Four transitions + payload seven bytes + member name 197 bytes.
    assert_eq(budget.remaining, 0)
    assert_eq(frame.workspace.peak, 3)
    assert_eq(frame.workspace.live, 0)
  }
}

///|
test "long property names never charge a whole spelling in one frame poll" {
  let name = "x".repeat(256)
  let value = capture(
    @admitted.object_value([(name, @admitted.number_value(7).unwrap())]).unwrap(),
  )
  let control = { remaining: 1000, max_frames: 10, }
  let workspace = row_workspace(20)
  let frame = expression_frame(
    property_name_expression(name),
    Map([("payload", value)]),
    [],
    control,
    workspace,
    None,
  ).unwrap()
  let mut complete = false
  for _ in 0..<400 {
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
        msg="a property name must not hide whole-Text work in one poll",
      )
    }
  }
  assert_true(complete)
  // Four transitions, seven payload-reference bytes, 256 member-name bytes.
  assert_eq(control.remaining, 733)
  assert_eq(workspace.live, 0)
}
