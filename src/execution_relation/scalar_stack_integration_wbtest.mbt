///|
test "integrated split composes with side padding math and extrema children" {
  for
    (source, expected) in [
      ("split(lpad('a,b',5,'x'),left(',!',1))", "[\"xxa\",\"b\"]"),
      ("split(rpad('a',3,','),right('x,',1))", "[\"a\",\"\",\"\"]"),
      (
        "split(lpad('a,b',greatest(5,log(100,10)),','),',')", "[\"\",\"\",\"a\",\"b\"]",
      ),
      ("split(right('😀a,β',least(4,pow(2,2))),',')", "[\"😀a\",\"β\"]"),
    ] {
    assert_eq(
      object_result_wire(run_expr("\"" + source + "\"").unwrap()),
      expected,
    )
  }
  for
    source in [
      "split(NULL,left('x',pow(0,-1)))", "split(lpad(NULL,greatest(NULL,pow(-2,0.5)),'x'),NULL)",
      "split(left('x',pow(0,-1)),to_string(1/0))",
    ] {
    guard run_expr("\"" + source + "\"") is Err(issue) else { fail(source) }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Pow, _, _),
    )
  }
  for
    source in [
      "if(false,split(NULL,left('x',pow(0,-1))),split('safe'))", "coalesce(split('safe'),split(NULL,left('x',pow(0,-1))))",
    ] {
    assert_eq(
      object_result_wire(run_expr("\"" + source + "\"").unwrap()),
      "[\"safe\"]",
    )
  }
  assert_true(run_expr("\"split(lpad(NULL,5,''),left(',',1))\"") is Ok(Null))
}

///|
test "integrated split retains independently counted nested logical limits" {
  let source = "\"split(lpad('a,b',5,'x'),left(',!',1))\""
  // LPAD work: 4 entries + twice operand weights (4+1+2) + output 6 = 24.
  // LEFT work: 3 entries + twice operand weights (3+1) + output 2 = 13.
  // SPLIT adds entry 1, consumes 6+2, and output weight 7: total 53.
  // Final wire is 11; two retained operand wires are 7+3: peak live 21.
  for quantum in [1, 7, 256] {
    for drain in [false, true] {
      let logical = logical_budget(
        {
          max_input_rows: 1L,
          max_value_bytes: 11L,
          max_live_value_bytes: 21L,
          max_work: 53L,
        },
        11,
        3,
        2,
      ).unwrap()
      let result = resume_test_expression(source, logical, quantum, drain~).unwrap()
      assert_eq(object_result_wire(result.value), "[\"xxa\",\"b\"]")
      assert_eq((logical.work, logical.peak, logical.live), (53L, 21L, 11L))
      release_logical_root(logical, result.root.unwrap()).unwrap()
      assert_eq(logical.live, 0L)
    }
  }
  for (work, live, bytes) in [(52L, 21L, 11L), (53L, 20L, 11L), (53L, 21L, 10L)] {
    let logical = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: bytes,
        max_live_value_bytes: live,
        max_work: work,
      },
      11,
      3,
      2,
    ).unwrap()
    let workspace = row_workspace(1000)
    assert_true(
      evaluate_expression_with_workspace(
        lowered(source),
        Map([]),
        [],
        { remaining: 100000, max_frames: 100, },
        workspace,
        logical_work=Some(logical),
      )
      is Err(_),
    )
    assert_eq((logical.live, workspace.live), (0L, 0))
  }
}

///|
test "integrated text and split cancellations preserve caller owned roots" {
  let source = "\"split(lpad('a,b',513,'x'),left(',!',1))\""
  for phase in [0, 1, 2, 3] {
    let logical = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: 10000L,
        max_live_value_bytes: 100000L,
        max_work: 100000L,
      },
      10000,
      1000,
      100,
    ).unwrap()
    let borrowed = retain_logical_value(logical, Number(7)).unwrap()
    let workspace = row_workspace(10000)
    assert_true(reserve_slots(workspace, 2))
    let frame = expression_frame(
      lowered(source),
      Map([]),
      [],
      { remaining: 100000, max_frames: 100, },
      workspace,
      Some(expression_roots(logical, 100)),
    ).unwrap()
    let mut found = false
    for _ in 0..<30000 {
      assert_true(advance_expression_frame(frame).unwrap() is None)
      let selected = match frame.state {
        TextFunction(state) =>
          state.kind == TextLPad &&
          (
            (phase == 0 && !state.building && state.padding_remaining == 400L) ||
            (phase == 1 && state.building && state.padding_remaining == 400L)
          )
        SplitFunction(state) =>
          (phase == 2 && !state.building && state.position == 64) ||
          (phase == 3 && state.admission is Some(_))
        _ => false
      }
      if selected {
        found = true
        break
      }
    }
    assert_true(found)
    let consumed = logical.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq((logical.work, logical.live, workspace.live), (consumed, 1L, 2))
    assert_false(borrowed.released)
    assert_true(frame.arrays.is_empty())
    assert_true(
      advance_expression_frame(frame) is Err({ kind: InvalidControlLimits, .. }),
    )
    assert_eq((logical.work, logical.live, workspace.live), (consumed, 1L, 2))
    release_logical_root(logical, borrowed).unwrap()
    release_slots(workspace, 2)
  }
}
