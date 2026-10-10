///|
// Independent STRING code-point-set expectations, not live BigQuery results.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#trim
test "trim sets remove scalar members rather than substrings or grapheme clusters" {
  for
    (input, set, both, left, right) in [
      ("xzxapplexxy", "xyz", "apple", "applexxy", "xzxapple"),
      ("xyxappleyxx", "yxxy", "apple", "appleyxx", "xyxapple"),
      ("  x  ", "x", "  x  ", "  x  ", "  x  "),
      (" aba ", " ", "aba", "aba ", " aba"),
      ("aba", "ab", "", "", ""),
      ("", "ab", "", "", ""),
      (" 😀 ", "", " 😀 ", " 😀 ", " 😀 "),
      (
        "😀😁a😁😀", "😀", "😁a😁", "😁a😁😀", "😀😁a😁",
      ),
      ("😀😁a😁😀", "😁😀", "a", "a😁😀", "😀😁a"),
      ("abaW̊", "Y̊", "abaW", "abaW̊", "abaW"),
      ("W̊aba", "Y̊", "W̊aba", "W̊aba", "W̊aba"),
      ("abaŪ̊", "Y̊", "abaŪ", "abaŪ̊", "abaŪ"),
      ("Ū̊aba", "Y̊", "Ū̊aba", "Ū̊aba", "Ū̊aba"),
      ("́é", "́", "e", "é", "́e"),
      ("éxé", "é", "éxé", "éxé", "éxé"),
      ("éxé", "é", "éxé", "éxé", "éxé"),
      ("\u{0}x\u{0}", "\u{0}", "x", "x\u{0}", "\u{0}x"),
      ("\u{feff}x\u{200b}", "\u{200b}\u{feff}", "x", "x\u{200b}", "\u{feff}x"),
      ("\r\nx\n\r", "\n", "\r\nx\n\r", "\r\nx\n\r", "\r\nx\n\r"),
      ("\r\nx\n\r", "\r\n", "x", "x\n\r", "\r\nx"),
    ] {
    for (tag, expected) in [("trim", both), ("ltrim", left), ("rtrim", right)] {
      guard evaluate_expression(
          borrowed_text_comparison(tag),
          Map([("left", Text(input)), ("right", Text(set))]),
          [],
          { remaining: 100000, max_frames: 10, },
        )
        is Ok(Text(actual)) else {
        fail("explicit trim set failed")
      }
      assert_eq(actual, expected)
    }
  }
}

///|
test "trim sets evaluate both operands once in order before strict NULL" {
  for tag in ["trim", "ltrim", "rtrim"] {
    for args in ["NULL, 'a'", "'a', NULL", "NULL, NULL", "NULL, ''", "'', NULL"] {
      assert_true(run_expr("\"" + tag + "(" + args + ")\"") is Ok(Null))
    }
    for
      args in [
        "NULL, if(1 / 0 > 0, 'a', 'b')", "if(1 / 0 > 0, 'a', 'b'), NULL", "'', if(1 / 0 > 0, 'a', 'b')",
        "if(1 / 0 > 0, 'a', 'b'), ''",
      ] {
      guard run_expr("\"" + tag + "(" + args + ")\"") is Err(issue) else {
        fail("trim set suppressed a demanded child failure")
      }
      assert_true(issue.kind is Scalar(ArithmeticFailure))
      assert_true(
        @lower.expression_body(issue.expression)
        is @lower.Binary(@lower.Divide, _, _),
      )
    }
    guard run_expr(
        "\"" + tag + "(if(sqrt(-1) > 0, 'a', 'b'), if(1 / 0 > 0, 'c', 'd'))\"",
      )
      is Err(issue) else {
      fail("first demanded failure missing")
    }
    assert_true(
      @lower.expression_body(issue.expression) is @lower.Unary(@lower.Sqrt, _),
    )
    for
      source in [
        "if(FALSE, " + tag + "(NULL, if(1 / 0 > 0, 'a', 'b')), 'safe')",
        "coalesce('safe', " + tag + "(NULL, if(1 / 0 > 0, 'a', 'b')))",
      ] {
      assert_true(run_expr("\"" + source + "\"") is Ok(Text("safe")))
    }
    for
      (left, right) in [
        (Number(1.0), Text("a")),
        (Text("a"), Boolean(true)),
        (Null, Number(1.0)),
      ] {
      assert_true(
        evaluate_expression(
          borrowed_text_comparison(tag),
          Map([("left", left), ("right", right)]),
          [],
          { remaining: 1000, max_frames: 10, },
        )
        is Err({ kind: Scalar(InvalidOperand), .. }),
      )
    }
  }
}

///|
test "trim set logical ledgers hold both operands and exact output across quanta" {
  // Input a*128 + emoji*128 + b*128 has weight769/wire770; set ba has
  // weight3/wire4. Work = three entries + 2*(769+3) + output weight.
  // Live peak includes BOTH operands plus output; workspace is output UTF16+2.
  let input = String::make(128, 'a') +
    String::make(128, '😀') +
    String::make(128, 'b')
  for
    (tag, expected, work, live, slots) in [
      ("trim", String::make(128, '😀'), 2060L, 1288L, 258),
      (
        "ltrim",
        String::make(128, '😀') + String::make(128, 'b'),
        2188L,
        1416L,
        386,
      ),
      (
        "rtrim",
        String::make(128, 'a') + String::make(128, '😀'),
        2188L,
        1416L,
        386,
      ),
    ] {
    let mut reference = (-1, -1)
    for quantum in [1, 7, 256] {
      for failure in 0..<4 {
        let logical = text_expression_budget(
          work - (if failure == 1 { 1L } else { 0L }),
          live - (if failure == 2 { 1L } else { 0L }),
        )
        let workspace = row_workspace(
          slots - (if failure == 3 { 1 } else { 0 }),
        )
        let frame = expression_frame(
          borrowed_text_comparison(tag),
          Map([("left", Text(input)), ("right", Text("ba"))]),
          [],
          { remaining: 100000, max_frames: 10, },
          workspace,
          Some(expression_roots(logical, 10)),
        ).unwrap()
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
              fail("exact trim set ledger")
            }
            assert_true(value.value is Text(text) && text == expected)
            assert_eq(
              (logical.work, logical.peak, workspace.peak),
              (work, live, slots),
            )
            if reference.0 < 0 {
              reference = (polls, frame.budget.remaining)
            } else {
              assert_eq((polls, frame.budget.remaining), reference)
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
          _ => fail("unknown boundary")
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
test "trim set membership scan sizing and construction cancel without releasing borrowed roots" {
  let input = String::make(128, 'a') +
    String::make(128, '😀') +
    String::make(128, 'b')
  let set = String::make(128, 'z') + "ba"
  for tag in ["trim", "ltrim", "rtrim"] {
    for phase in 0..<3 {
      for exhaust in [false, true] {
        let logical = text_expression_budget(10000L, 10000L)
        let borrowed_input = retain_logical_value(logical, Text(input)).unwrap()
        let borrowed_set = retain_logical_value(logical, Text(set)).unwrap()
        let workspace = row_workspace(1000)
        assert_true(reserve_slots(workspace, 3))
        let frame = expression_frame(
          borrowed_text_comparison(tag),
          Map([("left", Text(input)), ("right", Text(set))]),
          [],
          { remaining: 100000, max_frames: 10, },
          workspace,
          Some(expression_roots(logical, 10)),
        ).unwrap()
        let mut reached = false
        for _ in 0..<100000 {
          assert_true(advance_expression_frame(frame) is Ok(None))
          if frame.state is TextFunction(state) &&
            (if phase == 0 {
              state.trim_scanning && state.matched == 64
            } else if phase == 1 {
              !state.trim_scanning && !state.building && state.units == 64
            } else {
              state.building && state.position == state.trim_start + 64
            }) {
            assert_true(state.trim_explicit)
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
          (consumed, borrowed_input.bytes + borrowed_set.bytes, 3),
        )
        assert_false(borrowed_input.released)
        assert_false(borrowed_set.released)
        release_logical_root(logical, borrowed_input).unwrap()
        release_logical_root(logical, borrowed_set).unwrap()
        release_slots(workspace, 3)
        assert_eq((logical.live, workspace.live), (0L, 0))
      }
    }
  }
}

///|
test "trim sets preserve nested unary defaults and explicit empty set identity" {
  for
    (source, expected) in [
      ("trim(ltrim('　xxaxxx　'), 'x')", "axxx　"),
      ("ltrim(trim('　xxaxxx　'), 'x')", "axxx"),
      ("rtrim(trim('　xxaxxx　'), 'x')", "xxa"),
      ("trim(trim('　xxaxxx　'), 'x')", "a"),
      ("trim('　xxaxxx　', '')", "　xxaxxx　"),
    ] {
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Text(actual)) && actual == expected,
    )
  }
}

///|
test "trim set repeated membership comparisons consume exact bounded control work" {
  // Six expression transitions and names left/right cost15. Each of128
  // input scalars compares129 set scalars, or128 misses plus the end poll.
  // Add three finish transitions; absent membership also sizes/builds128 scalars.
  for tag in ["trim", "ltrim", "rtrim"] {
    for
      (set, expected, exact, slots) in [
        (String::make(128, 'z') + "a", "", 16530, 2),
        (String::make(128, 'z'), String::make(128, 'a'), 16786, 130),
        ("a" + String::make(128, 'z'), "", 146, 2),
      ] {
      for drain in [false, true] {
        for quantum in [1, 7, 256] {
          for short in [false, true] {
            let control = {
              remaining: exact - (if short { 1 } else { 0 }),
              max_frames: 10,
            }
            let workspace = row_workspace(slots)
            let frame = expression_frame(
              borrowed_text_comparison(tag),
              Map([("left", Text(String::make(128, 'a'))), ("right", Text(set))]),
              [],
              control,
              workspace,
              None,
            ).unwrap()
            let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
            let mut polls = 0
            while result is Ok(None) && polls < 20000 {
              for _ in 0..<quantum {
                let before = control.remaining
                let scanning = frame.state
                  is TextFunction({ trim_scanning: true, .. })
                result = advance_expression_frame(frame, drain~)
                polls += 1
                if !drain {
                  assert_true(before - control.remaining <= 64)
                  if scanning && before > 0 {
                    assert_eq(before - control.remaining, 1)
                  }
                }
                if !(result is Ok(None)) {
                  break
                }
              }
            }
            if short {
              assert_true(result is Err({ kind: ControlLimit, .. }))
            } else {
              assert_true(
                result is Ok(Some({ value: Text(actual), .. })) &&
                actual == expected,
              )
              assert_eq(control.remaining, 0)
            }
            assert_eq((workspace.peak, workspace.live), (slots, 0))
            assert_true(frame.closed)
          }
        }
      }
    }
  }
}
