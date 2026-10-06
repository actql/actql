///|
fn object_name_expression(name : String) -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"value\":{\"object\":{\"" +
    name +
    "\":{\"field\":\"id\"}}}}}]",
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
test "constructed object names never charge a whole spelling in one poll" {
  let name = "x".repeat(256)
  let control = { remaining: 1000, max_frames: 10, }
  let workspace = row_workspace(20)
  let frame = expression_frame(
    object_name_expression(name),
    Map([("id", Number(7))]),
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
          assert_eq(object_result_wire(result.value), "{\"" + name + "\":7}")
          complete = true
        }
      }
      assert_true(
        before - control.remaining <= 64,
        msg="an Object append must not hide whole-name work in one poll",
      )
    }
  }
  assert_true(complete)
  assert_eq(control.remaining, 735)
  assert_eq(workspace.live, 0)
}

///|
test "constructed object names preserve exact work live and workspace bounds" {
  let name = "x".repeat(256)
  // Two entries, produced/consumed scalar, Object weight 1+256+1: 262.
  // Object wire 262 plus its retained one-byte child peaks at 263.
  // The scalar uses the existing small root lane: three Object handles,
  // two pending name handles and three reserved field handles peak at eight.
  for quantum in [1, 7, 256] {
    for
      (work, live, slots, expected) in [
        (262L, 263L, 8, 0),
        (261L, 263L, 8, 1),
        (262L, 262L, 8, 2),
        (262L, 263L, 7, 3),
      ] {
      let logical = text_expression_budget(work, live)
      let workspace = row_workspace(slots)
      let frame = expression_frame(
        object_name_expression(name),
        Map([("id", Number(7))]),
        [],
        { remaining: 10000, max_frames: 10, },
        workspace,
        Some(expression_roots(logical, 10)),
      ).unwrap()
      let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
      for _ in 0..<1000 {
        for _ in 0..<quantum {
          if result is Ok(None) {
            result = advance_expression_frame(frame)
          }
        }
      }
      match expected {
        0 => {
          guard result is Ok(Some(result)) else { fail("exact Object bounds") }
          assert_eq(object_result_wire(result.value), "{\"" + name + "\":7}")
          assert_eq(
            (logical.work, logical.peak, workspace.peak),
            (262L, 263L, 8),
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
test "Object name sizing and charging preserve roots through exact-phase cancellation" {
  let name = "x".repeat(256)
  for phase in [0, 1] {
    let logical = text_expression_budget(10000L, 10000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(20)
    let frame = expression_frame(
      object_name_expression(name),
      Map([("id", Number(7))]),
      [],
      { remaining: 10000, max_frames: 10, },
      workspace,
      Some(expression_roots(logical, 10)),
    ).unwrap()
    let mut inside = false
    for _ in 0..<1000 {
      if !inside {
        assert_true(advance_expression_frame(frame).unwrap() is None)
        inside = frame.state is ObjectName(state) &&
          state.phase == phase &&
          state.offset == 64
      }
    }
    assert_true(inside)
    // One pre-existing caller root plus two entries and produce/consume.
    assert_eq(logical.work, 5L)
    assert_eq(logical.live, if phase == 0 { 4L } else { 264L })
    assert_true(frame.current_root is Some(_))
    assert_eq(frame.objects.length(), 1)
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq(logical.work, 5L)
    assert_eq((logical.live, workspace.live), (1L, 0))
    assert_false(borrowed.released)
    assert_eq(frame.objects.length(), 0)
    release_logical_root(logical, borrowed).unwrap()
    assert_eq(logical.live, 0L)
  }
}

///|
test "Object name wire refusal precedes control and Unicode NULL remains exact" {
  let name = "x".repeat(256)
  let logical = text_expression_budget(10000L, 262L)
  let frame = expression_frame(
    object_name_expression(name),
    Map([("id", Number(7))]),
    [],
    { remaining: 100, max_frames: 10, },
    row_workspace(20),
    Some(expression_roots(logical, 10)),
  ).unwrap()
  let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
  for _ in 0..<1000 {
    if result is Ok(None) {
      result = advance_expression_frame(frame)
    }
  }
  assert_true(result is Err({ kind: LogicalValue(LiveValueLimit), .. }))
  assert_eq(logical.live, 0L)
  let unicode = "x".repeat(63) + "😀" + "é".repeat(65)
  // Object 1+197+NULL 1, plus two entries and scalar produce/consume: 203.
  // Its wire is 206, while the child NULL wire occupies four more bytes.
  let logical = text_expression_budget(203L, 210L)
  let frame = expression_frame(
    object_name_expression(unicode),
    Map([("id", Null)]),
    [],
    { remaining: 10000, max_frames: 10, },
    row_workspace(20),
    Some(expression_roots(logical, 10)),
  ).unwrap()
  let mut result : EvaluatedValue? = None
  for _ in 0..<1000 {
    if result is None {
      result = advance_expression_frame(frame).unwrap()
    }
  }
  guard result is Some(result) else { fail("Unicode Object did not complete") }
  assert_eq(object_result_wire(result.value), "{\"" + unicode + "\":null}")
  assert_eq((logical.work, logical.peak), (203L, 210L))
  release_logical_root(logical, result.root.unwrap()).unwrap()
  assert_eq(logical.live, 0L)
}
