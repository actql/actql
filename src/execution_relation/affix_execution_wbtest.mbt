///|
// These are independent GoogleSQL STRING/default-comparison expectations,
// not observations from a live BigQuery service or product-generated results.
test "string affix predicates preserve exact retained Unicode and empty strings" {
  for
    (source, expected) in [
      ("starts_with('猫abc', '猫')", true),
      ("starts_with('猫abc', '猫a')", true),
      ("starts_with('abc', 'A')", false),
      ("starts_with('abc', 'bc')", false),
      ("starts_with('abc', 'abcd')", false),
      ("starts_with('abc', '')", true),
      ("starts_with('', '')", true),
      ("starts_with('', 'a')", false),
      ("starts_with('😀abc', '😀')", true),
      ("starts_with('éabc', 'é')", false),
      ("starts_with('éabc', 'e')", true),
      ("ends_with('abc', '')", true),
      ("ends_with('', '')", true),
      ("ends_with('', 'a')", false),
      ("ends_with('abc', 'bc')", true),
      ("ends_with('abc', 'BC')", false),
      ("ends_with('abc', 'ab')", false),
      ("ends_with('abc', 'xabc')", false),
      ("ends_with('abc😀', '😀')", true),
      ("ends_with('abc😀', '😁')", false),
      ("ends_with('café', '́')", true),
      ("ends_with('café', 'é')", false),
    ] {
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Boolean(actual)) &&
      actual == expected,
      msg=source,
    )
  }
  let input = Text("\r\n猫\r\n")
  for
    (op, part, expected) in [
      ("starts_with", Text("\r\n"), true),
      ("starts_with", Text("\n"), false),
      ("ends_with", Text("\r\n"), true),
      ("ends_with", Text("\r"), false),
    ] {
    assert_true(
      evaluate_expression(
        borrowed_text_comparison(op),
        Map([("left", input), ("right", part)]),
        [],
        { remaining: 1000, max_frames: 10, },
      )
      is Ok(Boolean(actual)) &&
      actual == expected,
    )
  }
}

///|
test "string affix predicates propagate NULL only after evaluating both arguments" {
  for op in ["starts_with", "ends_with"] {
    for args in ["NULL, 'a'", "'a', NULL", "NULL, NULL"] {
      assert_true(run_expr("\"" + op + "(" + args + ")\"") is Ok(Null))
    }
    for
      args in ["NULL, if(1 / 0 > 0, 'a', 'b')", "if(1 / 0 > 0, 'a', 'b'), NULL"] {
      guard run_expr("\"" + op + "(" + args + ")\"") is Err(issue) else {
        fail("NULL hid demanded child failure")
      }
      assert_true(issue.kind is Scalar(ArithmeticFailure))
      assert_true(
        @lower.expression_body(issue.expression)
        is @lower.Binary(@lower.Divide, _, _),
      )
    }
    assert_true(
      run_expr("\"if(FALSE, " + op + "(NULL, if(1 / 0 > 0, 'a', 'b')), TRUE)\"")
      is Ok(Boolean(true)),
    )
    guard run_expr(
        "\"" + op + "(if(sqrt(-1) > 0, 'a', 'b'), if(1 / 0 > 0, 'c', 'd'))\"",
      )
      is Err(issue) else {
      fail("first demanded failure missing")
    }
    assert_true(
      @lower.expression_body(issue.expression) is @lower.Unary(@lower.Sqrt, _),
    )
  }
}

///|
test "long string affix predicates yield through retained charging and matching" {
  let text = String::make(4096, 'g')
  for op in ["starts_with", "ends_with"] {
    let control = { remaining: 10000, max_frames: 10, }
    let workspace = row_workspace(2)
    let frame = expression_frame(
      borrowed_text_comparison(op),
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
    guard result is Some(value) else { fail("bounded affix did not terminate") }
    assert_true(value.value is Boolean(true))
    assert_true(polls > 12000)
    assert_eq(control.remaining, 10000 - 8192 - 15)
    assert_eq(workspace.live, 0)
  }
}

///|
test "string affix resumes preserve exact control boundaries and negative results" {
  let prefix = String::make(256, 'g')
  for op in ["starts_with", "ends_with"] {
    for drain in [false, true] {
      for limit in [527, 526] {
        let control = { remaining: limit, max_frames: 10, }
        let workspace = row_workspace(2)
        let frame = expression_frame(
          borrowed_text_comparison(op),
          Map([("left", Text(prefix)), ("right", Text(prefix))]),
          [],
          control,
          workspace,
          None,
        ).unwrap()
        let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
        for _ in 0..<2000 {
          result = advance_expression_frame(frame, drain~)
          if !(result is Ok(None)) {
            break
          }
        }
        if limit == 527 {
          assert_true(result is Ok(Some({ value: Boolean(true), .. })))
          assert_eq(control.remaining, 0)
        } else {
          assert_true(result is Err({ kind: ControlLimit, .. }))
        }
        assert_eq(workspace.live, 0)
      }
    }
    let workspace = row_workspace(2)
    assert_true(
      evaluate_expression_with_workspace(
        borrowed_text_comparison(op),
        Map([("left", Text(prefix + "x")), ("right", Text(prefix + "y"))]),
        [],
        { remaining: 2000, max_frames: 10, },
        workspace,
      )
      is Ok(Boolean(false)),
    )
    assert_eq(workspace.live, 0)
  }
}

///|
test "short multibyte affix cursors retain exact UTF8 control charging" {
  for (op, input) in [("starts_with", "😀é"), ("ends_with", "é😀")] {
    for drain in [false, true] {
      for limit in [25, 24] {
        let control = { remaining: limit, max_frames: 10, }
        let workspace = row_workspace(2)
        let frame = expression_frame(
          borrowed_text_comparison(op),
          Map([("left", Text(input)), ("right", Text("😀"))]),
          [],
          control,
          workspace,
          None,
        ).unwrap()
        let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
        for _ in 0..<100 {
          result = advance_expression_frame(frame, drain~)
          if !(result is Ok(None)) {
            break
          }
        }
        if limit == 25 {
          assert_true(result is Ok(Some({ value: Boolean(true), .. })))
          assert_eq(control.remaining, 0)
        } else {
          assert_true(result is Err({ kind: ControlLimit, .. }))
        }
        assert_eq(workspace.live, 0)
      }
    }
  }
}

///|
test "string affix functions keep independent exact logical and live limits" {
  // Three entries, two produced Text weights (257), two consumed operands,
  // and one Boolean result give 1032 work. Input roots peak at 516 bytes.
  for op in ["starts_with", "ends_with"] {
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
        borrowed_text_comparison(op),
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
            fail("exact affix logical boundary")
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
}

///|
test "string affix cancellation during charging and matching releases only owned roots" {
  for op in ["starts_with", "ends_with"] {
    for phase in [0, 1, 2] {
      let logical = text_expression_budget(100000L, 100000L)
      let borrowed = retain_logical_value(logical, Text("external")).unwrap()
      let workspace = row_workspace(20)
      let text = Text(String::make(256, 'g'))
      let frame = expression_frame(
        borrowed_text_comparison(op),
        Map([("left", text), ("right", text)]),
        [],
        { remaining: 10000, max_frames: 10, },
        workspace,
        Some(expression_roots(logical, 10)),
      ).unwrap()
      let mut reached = false
      for _ in 0..<2000 {
        assert_true(advance_expression_frame(frame).unwrap() is None)
        if frame.state is CompareBinary(state) &&
          state.phase == phase &&
          (phase != 2 || state.offset >= 80) {
          reached = true
          break
        }
      }
      assert_true(reached)
      let work = logical.work
      close_expression_frame(frame)
      close_expression_frame(frame)
      assert_eq(logical.work, work)
      assert_false(borrowed.released)
      assert_eq((logical.live, workspace.live), (borrowed.bytes, 0))
      release_logical_root(logical, borrowed).unwrap()
      assert_eq(logical.live, 0L)
    }
  }
}
