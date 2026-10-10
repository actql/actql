///|
test "substring adopts GoogleSQL zero negative and omitted length positions" {
  for
    (source, expected) in [
      ("substring('apple',2)", "pple"),
      ("substring('apple',2,2)", "pp"),
      ("substring('apple',-2)", "le"),
      ("substring('apple',1,123)", "apple"),
      ("substring('apple',123)", ""),
      ("substring('apple',123,5)", ""),
      ("substring('abcd',0,2)", "ab"),
      ("substring('abcd',-1,2)", "d"),
      ("substring('abcd',-4,2)", "ab"),
      ("substring('abcd',-5,2)", "ab"),
      ("substring('abcd',-9007199254740991,2)", "ab"),
      ("substring('abcd',9007199254740991,2)", ""),
      ("substring('abcd',2,9007199254740991)", "bcd"),
      ("substring('abcd',-2,9007199254740991)", "cd"),
      ("substring('abcd',2,0)", ""),
      ("substring('',0)", ""),
      ("substring('',-1,1)", ""),
      ("substring('😀éx',1,1)", "😀"),
      ("substring('😀éx',2,2)", "é"),
      ("substring('😀éx',3,1)", "́"),
      ("substring('😀éx',-2,1)", "́"),
      ("substring('a\\r\\nb',2,2)", "\r\n"),
    ] {
    guard run_expr("\"" + source + "\"") is Ok(Text(actual)) else {
      fail(source)
    }
    assert_eq(actual, expected)
  }
}

///|
test "substring applies strict NULL after every demanded child" {
  for
    source in [
      "substring(NULL,1)", "substring('abc',NULL)", "substring('abc',1,NULL)", "substring(NULL,1,-1)",
      "substring('abc',NULL,-1)", "substring(NULL,0.5)",
    ] {
    assert_true(run_expr("\"" + source + "\"") is Ok(Null))
  }
  for
    source in [
      "substring('abc',1,-1)", "substring('',99,-1)", "substring('abc',0.5)", "substring('abc',1,0.5)",
      "substring('abc',9007199254740991 + 1)", "substring('abc',1,9007199254740991 + 1)",
    ] {
    assert_true(
      run_expr("\"" + source + "\"")
      is Err({ kind: Scalar(InvalidOperand), .. }),
    )
  }
  for
    source in [
      "substring(NULL,1 / 0)", "substring(NULL,1,1 / 0)", "substring('abc',0.5,1 / 0)",
    ] {
    assert_true(
      run_expr("\"" + source + "\"")
      is Err({ kind: Scalar(ArithmeticFailure), .. }),
    )
  }
  for
    source in [
      "if(false,substring('abc',1,-1),'safe')", "coalesce('safe',substring('abc',1,-1))",
    ] {
    assert_true(run_expr("\"" + source + "\"") is Ok(Text("safe")))
  }
}

///|
fn substring_text_expression(length? : Bool = true) -> @lower.Expression {
  let body = "{\"substring\":{\"value\":{\"field\":\"payload\"},\"start\":{\"literal\":-128}" +
    (if length { ",\"length\":{\"literal\":64}" } else { "" }) +
    "}}"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":" +
    body +
    "}}]",
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
fn substring_text_frame(
  logical : LogicalBudget,
  workspace : RowWorkspace,
  length? : Bool = true,
) -> ExpressionFrame {
  expression_frame(
    substring_text_expression(length~),
    Map([("payload", Text(String::make(256, '😀')))]),
    [],
    { remaining: 100000, max_frames: 10, },
    workspace,
    Some(expression_roots(logical, 10)),
  ).unwrap()
}

///|
test "substring holds every operand once and obeys exact work live byte workspace limits" {
  // Input has weight 1025 and wire 1026. Numeric operands each weigh 1;
  // their canonical wires are -128 (4 bytes) and 64 (2 bytes). Result lengths
  // are 64/128 scalars (weight 257/513, wire 258/514, UTF-16 128/256).
  // Work = expression entries + twice each operand weight + result weight.
  // The multi-argument continuation holds 3*n+3 slots plus the output units.
  for
    (length, work, live, slots, size) in [
      (true, 2315L, 1290L, 140, 64),
      (false, 2568L, 1544L, 265, 128),
    ] {
    let mut expected_polls = -1
    let mut expected_control = -1
    for quantum in [1, 7, 256] {
      for failure in 0..<4 {
        let logical = text_expression_budget(
          work - (if failure == 1 { 1L } else { 0L }),
          live - (if failure == 2 { 1L } else { 0L }),
        )
        let workspace = row_workspace(
          slots - (if failure == 3 { 1 } else { 0 }),
        )
        let frame = substring_text_frame(logical, workspace, length~)
        let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
        let mut polls = 0
        while polls < 10000 && result is Ok(None) {
          for _ in 0..<quantum {
            let before = frame.budget.remaining
            result = advance_expression_frame(frame)
            assert_true(before - frame.budget.remaining <= 64)
            polls += 1
            if !(result is Ok(None)) {
              break
            }
          }
        }
        match failure {
          0 => {
            guard result is Ok(Some(value)) else {
              fail("exact substring boundary")
            }
            assert_true(
              value.value is Text(actual) &&
              actual == String::make(size, '😀'),
            )
            assert_eq(
              (logical.work, logical.peak, workspace.peak),
              (work, live, slots),
            )
            if expected_polls < 0 {
              expected_polls = polls
              expected_control = frame.budget.remaining
            } else {
              assert_eq(
                (polls, frame.budget.remaining),
                (expected_polls, expected_control),
              )
            }
            release_logical_root(logical, value.root.unwrap()).unwrap()
          }
          1 =>
            assert_true(
              result
              is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
            )
          2 =>
            assert_true(
              result is Err({ kind: LogicalValue(LiveValueLimit), .. }),
            )
          3 => assert_true(result is Err({ kind: WorkspaceLimit, .. }))
          _ => fail("substring resource selection")
        }
        let work = logical.work
        close_expression_frame(frame)
        close_expression_frame(frame)
        assert_eq((logical.work, logical.live, workspace.live), (work, 0L, 0))
      }
    }
  }
}

///|
test "substring counting boundaries sizing construction cancel without refund or borrowed release" {
  for phase in 0..<4 {
    for exhaust in [false, true] {
      let logical = text_expression_budget(10000L, 10000L)
      let borrowed = retain_logical_value(
        logical,
        Text(String::make(256, '😀')),
      ).unwrap()
      let workspace = row_workspace(1000)
      assert_true(reserve_slots(workspace, 3))
      let frame = substring_text_frame(logical, workspace)
      let mut reached = false
      for _ in 0..<10000 {
        assert_true(advance_expression_frame(frame) is Ok(None))
        if frame.state is TextFunction(state) &&
          (if phase == 0 {
            state.substring_phase == 1 && state.position == 64
          } else if phase == 1 {
            state.substring_phase == 2 && state.position == 64
          } else if phase == 2 {
            state.substring_phase == 3 && !state.building && state.units == 64
          } else {
            state.building && state.position == state.trim_start + 64
          }) {
          reached = true
          break
        }
      }
      assert_true(reached)
      let consumed = logical.work
      assert_true(consumed > 1025L)
      if exhaust {
        frame.budget.remaining = 0
        assert_true(
          advance_expression_frame(frame) is Err({ kind: ControlLimit, .. }),
        )
      }
      close_expression_frame(frame)
      close_expression_frame(frame)
      assert_eq(
        (logical.work, logical.live, workspace.live),
        (consumed, borrowed.bytes, 3),
      )
      assert_false(borrowed.released)
      assert_true(
        advance_expression_frame(frame)
        is Err({ kind: InvalidControlLimits, .. }),
      )
      release_logical_root(logical, borrowed).unwrap()
      release_slots(workspace, 3)
    }
  }
}

///|
test "substring keeps left to right child failure identity before its own domain check" {
  guard run_expr("\"substring(to_string(sqrt(-1)),1 / 0,-1)\"") is Err(issue) else {
    fail("missing first substring child failure")
  }
  assert_true(
    @lower.expression_body(issue.expression) is @lower.Unary(@lower.Sqrt, _),
  )
  guard run_expr("\"substring('abc',0.5,1 / 0)\"") is Err(issue) else {
    fail("missing supplied length failure")
  }
  assert_true(
    @lower.expression_body(issue.expression)
    is @lower.Binary(@lower.Divide, _, _),
  )
}
