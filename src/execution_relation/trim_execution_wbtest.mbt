///|
fn trim_text_expression() -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":{\"trim\":{\"field\":\"payload\"}}}}]",
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
fn trim_text_frame(
  logical : LogicalBudget,
  workspace : RowWorkspace,
  input? : String = String::make(128, ' ') +
    String::make(128, '😀') +
    String::make(128, ' '),
) -> ExpressionFrame {
  expression_frame(
    trim_text_expression(),
    Map([("payload", Text(input))]),
    [],
    { remaining: 100000, max_frames: 10, },
    workspace,
    Some(expression_roots(logical, 10)),
  ).unwrap()
}

///|
test "trim executes all Unicode 16 White_Space points and preserves interior scalars" {
  // The independent PropList set is deliberately enumerated, not obtained
  // from the implementation predicate, host trim, or a product result.
  let whitespace = [
    0x0009, 0x000a, 0x000b, 0x000c, 0x000d, 0x0020, 0x0085, 0x00a0, 0x1680, 0x2000,
    0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
    0x2028, 0x2029, 0x202f, 0x205f, 0x3000,
  ]
  let expression = trim_text_expression()
  for code in whitespace {
    let edge = String::make(2, code.unsafe_to_char())
    for
      (input, expected) in [
        (edge, ""),
        (edge + "😀é" + edge, "😀é"),
        ("a" + edge + "b", "a" + edge + "b"),
      ] {
      guard evaluate_expression(
          expression,
          Map([("payload", Text(input))]),
          [],
          { remaining: 100000, max_frames: 10, },
        )
        is Ok(Text(actual)) else {
        fail("Unicode TRIM failed")
      }
      assert_eq(actual, expected)
    }
  }
  for
    (input, expected) in [
      ("", ""),
      (" a\r\nb ", "a\r\nb"),
      (" 😀é　", "😀é"),
      ("　é ", "é"),
      (" \u{feff}x\u{feff} ", "\u{feff}x\u{feff}"),
      (" \u{200b}x\u{200b} ", "\u{200b}x\u{200b}"),
      ("\u{feff} x \u{feff}", "\u{feff} x \u{feff}"),
      (" ́x́ ", "́x́"),
    ] {
    guard evaluate_expression(expression, Map([("payload", Text(input))]), [], {
        remaining: 100000,
        max_frames: 10,
      })
      is Ok(Text(actual)) else {
      fail("preserved TRIM operand failed")
    }
    assert_eq(actual, expected)
  }
  for
    code in [
      0x0000, 0x0008, 0x000e, 0x001c, 0x001f, 0x0021, 0x0084, 0x0086, 0x009f, 0x00a1,
      0x167f, 0x1681, 0x180e, 0x1fff, 0x200b, 0x2027, 0x202a, 0x202e, 0x2030, 0x205e,
      0x2060, 0x2fff, 0x3001, 0xfeff, 0x1f600,
    ] {
    let edge = String::make(1, code.unsafe_to_char())
    let retained = edge + " x " + edge
    guard evaluate_expression(
        expression,
        Map([("payload", Text(" " + retained + " "))]),
        [],
        { remaining: 100000, max_frames: 10, },
      )
      is Ok(Text(actual)) else {
      fail("non-White_Space boundary failed")
    }
    assert_eq(actual, retained)
  }
}

///|
test "trim preserves strict NULL lazy demand and scalar domain refusal" {
  assert_true(run_expr("\"trim(NULL)\"") is Ok(Null))
  assert_true(
    run_expr("\"if(FALSE, trim(to_string(1 / 0)), 'safe')\"")
    is Ok(Text("safe")),
  )
  assert_true(
    run_expr("\"trim(to_string(1 / 0))\"")
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  for value in [Number(9), Boolean(true)] {
    assert_true(
      evaluate_expression(
        trim_text_expression(),
        Map([("payload", value)]),
        [],
        { remaining: 10000, max_frames: 10, },
      )
      is Err({ kind: Scalar(InvalidOperand), .. }),
    )
  }
}

///|
test "trim obeys exact independent logical work live bytes and workspace ledgers" {
  // 128 SPACE + 128 astral scalars + 128 NBSP: input weight 897/wire 898.
  // Result is 128 astral scalars: weight 513/wire 514 and 256 UTF-16 units.
  // Two entries + twice input weight + output weight = 2309 logical work.
  // Input and output roots overlap at 1412 bytes; two slots + 256 output units.
  for quantum in [1, 7, 256] {
    for failure in 0..<4 {
      let logical = text_expression_budget(
        2309L - (if failure == 1 { 1L } else { 0L }),
        1412L - (if failure == 2 { 1L } else { 0L }),
      )
      let workspace = row_workspace(258 - (if failure == 3 { 1 } else { 0 }))
      let frame = trim_text_frame(logical, workspace)
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
            fail("exact TRIM resource boundary")
          }
          assert_true(
            value.value is Text(text) && text == String::make(128, '😀'),
          )
          assert_eq(
            (logical.work, logical.peak, workspace.peak),
            (2309L, 1412L, 258),
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
        _ => fail("unknown boundary case")
      }
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}

///|
test "trim scan sizing and construction stop without replay or borrowed root release" {
  for phase in 0..<3 {
    for exhaust in [false, true] {
      let logical = text_expression_budget(10000L, 10000L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(1000)
      let frame = trim_text_frame(logical, workspace)
      let mut reached = false
      for _ in 0..<10000 {
        assert_true(advance_expression_frame(frame) is Ok(None))
        if frame.state is TextFunction(state) &&
          (if phase == 0 {
            state.trim_scanning && state.position == 64
          } else if phase == 1 {
            !state.trim_scanning && !state.building && state.units == 64
          } else {
            state.building && state.position == 192
          }) {
          reached = true
          break
        }
      }
      assert_true(reached)
      let consumed = logical.work
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
        (consumed, borrowed.bytes, 0),
      )
      assert_false(borrowed.released)
      assert_true(
        advance_expression_frame(frame)
        is Err({ kind: InvalidControlLimits, .. }),
      )
      release_logical_root(logical, borrowed).unwrap()
      assert_eq(logical.live, 0L)
    }
  }
}

///|
test "trim whitespace-only scans yield and allocate only the admitted empty result" {
  let logical = text_expression_budget(1541L, 772L)
  let workspace = row_workspace(11)
  // 256 U+3000: input weight 769, wire 770; empty output weight 1, wire 2.
  let frame = trim_text_frame(
    logical,
    workspace,
    input=String::make(256, '　'),
  )
  let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
  let mut scanned = 0
  for _ in 0..<10000 {
    result = advance_expression_frame(frame)
    if frame.state is TextFunction(state) && state.trim_scanning {
      assert_true(state.position - scanned <= 1)
      scanned = state.position
      assert_eq(state.units, 0)
      assert_true(state.builder is None)
    }
    if !(result is Ok(None)) {
      break
    }
  }
  guard result is Ok(Some(value)) else { fail("empty TRIM result") }
  assert_true(value.value is Text(""))
  assert_eq((logical.work, logical.peak, workspace.peak), (1541L, 772L, 11))
  release_logical_root(logical, value.root.unwrap()).unwrap()
  assert_eq((logical.live, workspace.live), (0L, 0))
}
