///|
fn side_trim_text_expression(
  tag : String,
  skipped? : Bool = false,
) -> @lower.Expression {
  let body = "{\"" + tag + "\":{\"field\":\"payload\"}}"
  let selected = if skipped {
    "{\"if\":[{\"literal\":false}," + body + ",{\"literal\":\"safe\"}]}"
  } else {
    body
  }
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":" +
    selected +
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
fn side_trim_text_frame(
  tag : String,
  logical : LogicalBudget,
  workspace : RowWorkspace,
  input? : String = String::make(128, ' ') +
    String::make(128, '😀') +
    String::make(128, ' '),
) -> ExpressionFrame {
  expression_frame(
    side_trim_text_expression(tag),
    Map([("payload", Text(input))]),
    [],
    { remaining: 100000, max_frames: 10, },
    workspace,
    Some(expression_roots(logical, 10)),
  ).unwrap()
}

///|
test "side trim executes all Unicode 16 White_Space points on only the selected edge" {
  // This independent PropList enumeration does not call the implementation's
  // predicate, a host trim function, or a generated product oracle.
  let whitespace = [
    0x0009, 0x000a, 0x000b, 0x000c, 0x000d, 0x0020, 0x0085, 0x00a0, 0x1680, 0x2000,
    0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
    0x2028, 0x2029, 0x202f, 0x205f, 0x3000,
  ]
  assert_eq(whitespace.length(), 25)
  for (tag, left) in [("ltrim", true), ("rtrim", false)] {
    let expression = side_trim_text_expression(tag)
    for code in whitespace {
      let edge = String::make(2, code.unsafe_to_char())
      for
        (input, expected) in [
          (edge, ""),
          (
            edge + "😀é" + edge,
            if left {
              "😀é" + edge
            } else {
              edge + "😀é"
            },
          ),
          (edge + "😀é", if left { "😀é" } else { edge + "😀é" }),
          ("😀é" + edge, if left { "😀é" + edge } else { "😀é" }),
          ("a" + edge + "b", "a" + edge + "b"),
        ] {
        guard evaluate_expression(
            expression,
            Map([("payload", Text(input))]),
            [],
            { remaining: 100000, max_frames: 10, },
          )
          is Ok(Text(actual)) else {
          fail("Unicode side trim failed")
        }
        assert_eq(actual, expected)
      }
    }
  }
}

///|
test "side trim preserves non White_Space neighbors interior and raw Unicode scalars" {
  for (tag, left) in [("ltrim", true), ("rtrim", false)] {
    let expression = side_trim_text_expression(tag)
    for
      (input, expected_left, expected_right) in [
        ("", "", ""),
        (" a\r\nb ", "a\r\nb ", " a\r\nb"),
        (" 😀é　", "😀é　", " 😀é"),
        ("　é ", "é ", "　é"),
        (" \u{feff}x\u{feff} ", "\u{feff}x\u{feff} ", " \u{feff}x\u{feff}"),
        (" \u{200b}x\u{200b} ", "\u{200b}x\u{200b} ", " \u{200b}x\u{200b}"),
        (" \u{180e}x\u{180e} ", "\u{180e}x\u{180e} ", " \u{180e}x\u{180e}"),
        ("\u{feff} x \u{feff}", "\u{feff} x \u{feff}", "\u{feff} x \u{feff}"),
        (" ́x́ ", "́x́ ", " ́x́"),
        (
          " \u{0000}😀\u{0000} ", "\u{0000}😀\u{0000} ", " \u{0000}😀\u{0000}",
        ),
      ] {
      guard evaluate_expression(
          expression,
          Map([("payload", Text(input))]),
          [],
          { remaining: 100000, max_frames: 10, },
        )
        is Ok(Text(actual)) else {
        fail("preserved side trim operand failed")
      }
      assert_eq(actual, if left { expected_left } else { expected_right })
    }
    for
      code in [
        0x0000, 0x0008, 0x000e, 0x001c, 0x001f, 0x0021, 0x0084, 0x0086, 0x009f, 0x00a1,
        0x167f, 0x1681, 0x180e, 0x1fff, 0x200b, 0x2027, 0x202a, 0x202e, 0x2030, 0x205e,
        0x2060, 0x2fff, 0x3001, 0xfeff, 0x1f600,
      ] {
      let edge = String::make(1, code.unsafe_to_char())
      let retained = edge + " x " + edge
      for
        (input, expected) in [
          (retained, retained),
          (
            " " + retained + " ",
            if left {
              retained + " "
            } else {
              " " + retained
            },
          ),
        ] {
        guard evaluate_expression(
            expression,
            Map([("payload", Text(input))]),
            [],
            { remaining: 100000, max_frames: 10, },
          )
          is Ok(Text(actual)) else {
          fail("non-White_Space side trim boundary failed")
        }
        assert_eq(actual, expected)
      }
    }
  }
}

///|
test "side trim preserves strict NULL lazy demand and scalar domain refusal" {
  for tag in ["ltrim", "rtrim"] {
    assert_true(run_expr("\"" + tag + "(NULL)\"") is Ok(Null))
    assert_true(
      run_expr("\"if(FALSE, " + tag + "(to_string(1 / 0)), 'safe')\"")
      is Ok(Text("safe")),
    )
    assert_true(
      run_expr("\"coalesce('safe', " + tag + "(to_string(1 / 0)))\"")
      is Ok(Text("safe")),
    )
    assert_true(
      run_expr("\"" + tag + "(to_string(1 / 0))\"")
      is Err({ kind: Scalar(ArithmeticFailure), .. }),
    )
    assert_true(
      run_expr("\"if(TRUE, " + tag + "(to_string(1 / 0)), 'safe')\"")
      is Err({ kind: Scalar(ArithmeticFailure), .. }),
    )
    assert_true(
      evaluate_expression(
        side_trim_text_expression(tag),
        Map([("payload", Null)]),
        [],
        { remaining: 10000, max_frames: 10, },
      )
      is Ok(Null),
    )
    for value in [Number(9), Boolean(true)] {
      assert_true(
        evaluate_expression(
          side_trim_text_expression(tag),
          Map([("payload", value)]),
          [],
          { remaining: 10000, max_frames: 10, },
        )
        is Err({ kind: Scalar(InvalidOperand), .. }),
      )
      assert_true(
        evaluate_expression(
          side_trim_text_expression(tag, skipped=true),
          Map([("payload", value)]),
          [],
          { remaining: 10000, max_frames: 10, },
        )
        is Ok(Text("safe")),
      )
    }
  }
}

///|
test "nested side trims keep each selected boundary independent" {
  for
    (source, expected) in [
      ("ltrim(rtrim('　😀é '))", "😀é"),
      ("rtrim(ltrim('　😀é '))", "😀é"),
      ("ltrim(ltrim('　😀é '))", "😀é "),
      ("rtrim(rtrim('　😀é '))", "　😀é"),
      ("ltrim(rtrim(ltrim('　😀é ')))", "😀é"),
      ("rtrim(ltrim('　  '))", ""),
      ("ltrim(rtrim(''))", ""),
    ] {
    guard run_expr("\"" + source + "\"") is Ok(Text(actual)) else {
      fail("nested side trim failed")
    }
    assert_eq(actual, expected)
  }
  assert_true(run_expr("\"ltrim(rtrim(NULL))\"") is Ok(Null))
  assert_true(run_expr("\"rtrim(ltrim(NULL))\"") is Ok(Null))
}

///|
test "side trim obeys independent exact work live byte and workspace ledgers across quanta" {
  // Input: 128 SPACE + 128 astral emoji + 128 NBSP, weight 897/wire 898.
  // LTRIM: emoji + NBSP, weight 769/wire 770; RTRIM: SPACE + emoji,
  // weight 641/wire 642. Each output has 384 UTF-16 units plus two slots.
  // Work is two entries + twice input weight + output weight; live bytes
  // are the original input and complete output roots held simultaneously.
  for
    (tag, expected, work, live) in [
      (
        "ltrim",
        String::make(128, '😀') + String::make(128, ' '),
        2565L,
        1668L,
      ),
      (
        "rtrim",
        String::make(128, ' ') + String::make(128, '😀'),
        2437L,
        1540L,
      ),
    ] {
    let mut reference_polls = -1
    let mut reference_control = -1
    for quantum in [1, 7, 256] {
      for failure in 0..<4 {
        let logical = text_expression_budget(
          work - (if failure == 1 { 1L } else { 0L }),
          live - (if failure == 2 { 1L } else { 0L }),
        )
        let workspace = row_workspace(386 - (if failure == 3 { 1 } else { 0 }))
        let frame = side_trim_text_frame(tag, logical, workspace)
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
              fail("exact side trim resource boundary")
            }
            assert_true(value.value is Text(text) && text == expected)
            assert_eq(
              (logical.work, logical.peak, workspace.peak),
              (work, live, 386),
            )
            if reference_polls < 0 {
              reference_polls = polls
              reference_control = frame.budget.remaining
            } else {
              assert_eq(
                (polls, frame.budget.remaining),
                (reference_polls, reference_control),
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
          _ => fail("unknown side trim boundary case")
        }
        let consumed = logical.work
        close_expression_frame(frame)
        close_expression_frame(frame)
        assert_eq(
          (logical.work, logical.live, workspace.live),
          (consumed, 0L, 0),
        )
      }
    }
  }
}

///|
test "side trim scan sizing and construction stop without refund or borrowed root release" {
  let input = String::make(128, ' ') +
    String::make(128, '😀') +
    String::make(128, ' ')
  for tag in ["ltrim", "rtrim"] {
    for phase in 0..<3 {
      for exhaust in [false, true] {
        let logical = text_expression_budget(10000L, 10000L)
        let borrowed = retain_logical_value(logical, Text(input)).unwrap()
        let workspace = row_workspace(1000)
        assert_true(reserve_slots(workspace, 3))
        let frame = side_trim_text_frame(tag, logical, workspace, input~)
        let mut reached = false
        for _ in 0..<10000 {
          assert_true(advance_expression_frame(frame) is Ok(None))
          if frame.state is TextFunction(state) &&
            (if phase == 0 {
              state.trim_scanning && state.position == 64
            } else if phase == 1 {
              !state.trim_scanning && !state.building && state.units == 64
            } else {
              state.building && state.position == state.trim_start + 64
            }) {
            reached = true
            break
          }
        }
        assert_true(reached)
        let consumed = logical.work
        assert_true(consumed > 897L)
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
        assert_eq((logical.live, workspace.live), (0L, 0))
      }
    }
  }
}

///|
test "side trim whitespace only scan yields and retains exact empty output resource bounds" {
  // Independently: 256 U+3000 have weight 769/wire 770. Empty output has
  // weight 1/wire 2. Work = 2 + 2 * 769 + 1; overlap = 770 + 2.
  // Eleven workspace slots are inherited from operand measurement; no
  // proportional output buffer is needed for the empty result.
  for tag in ["ltrim", "rtrim"] {
    for quantum in [1, 7, 256] {
      for failure in 0..<4 {
        let logical = text_expression_budget(
          1541L - (if failure == 1 { 1L } else { 0L }),
          772L - (if failure == 2 { 1L } else { 0L }),
        )
        let workspace = row_workspace(11 - (if failure == 3 { 1 } else { 0 }))
        let frame = side_trim_text_frame(
          tag,
          logical,
          workspace,
          input=String::make(256, '　'),
        )
        let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
        let mut scanned = 0
        let mut polls = 0
        while polls < 10000 && result is Ok(None) {
          for _ in 0..<quantum {
            let before = frame.budget.remaining
            result = advance_expression_frame(frame)
            assert_true(before - frame.budget.remaining <= 64)
            polls += 1
            if frame.state is TextFunction(state) && state.trim_scanning {
              assert_true(state.position - scanned <= 1)
              scanned = state.position
              assert_eq((state.units, state.allocated), (0, 0))
              assert_true(state.builder is None)
            }
            if !(result is Ok(None)) {
              break
            }
          }
        }
        match failure {
          0 => {
            guard result is Ok(Some(value)) else {
              fail("empty side trim result")
            }
            assert_true(value.value is Text(""))
            assert_eq(scanned, 256)
            assert_eq(
              (logical.work, logical.peak, workspace.peak),
              (1541L, 772L, 11),
            )
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
          _ => fail("unknown empty side trim boundary case")
        }
        let consumed = logical.work
        close_expression_frame(frame)
        assert_eq(
          (logical.work, logical.live, workspace.live),
          (consumed, 0L, 0),
        )
      }
    }
  }
}
