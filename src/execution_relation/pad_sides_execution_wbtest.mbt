///|
test "side slices use Unicode scalar boundaries and clamp oversized lengths" {
  for
    (source, expected) in [
      ("left('banana',3)", "ban"),
      ("right('apple',3)", "ple"),
      ("left('abc',0)", ""),
      ("right('abc',0)", ""),
      ("left('',1)", ""),
      ("right('',1)", ""),
      ("left('abc',9007199254740991)", "abc"),
      ("right('abc',9007199254740991)", "abc"),
      ("left('😀éx',2)", "😀e"),
      ("right('😀éx',2)", "́x"),
      ("left('😀éx',3)", "😀é"),
      ("right('😀éx',3)", "éx"),
      ("left('a\\r\\nb',2)", "a\r"),
      ("right('a\\r\\nb',2)", "\nb"),
    ] {
    guard run_expr("\"" + source + "\"") is Ok(Text(actual)) else {
      fail(source)
    }
    assert_eq(actual, expected)
  }
}

///|
test "padding repeats only the needed scalar prefix and truncates original input" {
  for
    (source, expected) in [
      ("lpad('c',5)", "    c"),
      ("rpad('c',5)", "c    "),
      ("lpad('abc',10,'ghd')", "ghdghdgabc"),
      ("rpad('abc',10,'ghd')", "abcghdghdg"),
      ("lpad('abc',2,'d')", "ab"),
      ("rpad('abc',2,'d')", "ab"),
      ("lpad('abc',3,'d')", "abc"),
      ("rpad('abc',3,'d')", "abc"),
      ("lpad('abc',0)", ""),
      ("rpad('abc',0)", ""),
      ("lpad('',3,'ab')", "aba"),
      ("rpad('',3,'ab')", "aba"),
      ("lpad('',0,'x')", ""),
      ("rpad('',0,'x')", ""),
      ("lpad('😀éx',3,'z')", "😀é"),
      ("rpad('😀éx',3,'z')", "😀é"),
      ("lpad('X',6,'😀é')", "😀é😀eX"),
      ("rpad('X',6,'😀é')", "X😀é😀e"),
      ("lpad('x',4,'\\r\\n')", "\r\n\rx"),
      ("rpad('x',4,'\\r\\n')", "x\r\n\r"),
    ] {
    guard run_expr("\"" + source + "\"") is Ok(Text(actual)) else {
      fail(source)
    }
    assert_eq(actual, expected)
  }
  for name in ["lpad", "rpad"] {
    guard run_expr(
        "{\"" +
        name +
        "\":[{\"literal\":\"a\\u0000\"},{\"literal\":5},{\"literal\":\"\\u0000b\"}]}",
      )
      is Ok(Text(actual)) else {
      fail("NUL padding")
    }
    assert_eq(
      actual,
      if name == "lpad" {
        "\u{0000}b\u{0000}a\u{0000}"
      } else {
        "a\u{0000}\u{0000}b\u{0000}"
      },
    )
  }
}

///|
test "side slice and padding domain checks follow successful strict children" {
  for name in ["left", "right", "lpad", "rpad"] {
    for args in ["NULL,-1", "NULL,0.5", "'abc',NULL"] {
      assert_true(run_expr("\"" + name + "(" + args + ")\"") is Ok(Null))
    }
    for args in ["'abc',-1", "'',-1", "'abc',0.5", "'abc',9007199254740991+1"] {
      assert_true(
        run_expr("\"" + name + "(" + args + ")\"")
        is Err({ kind: Scalar(InvalidOperand), .. }),
      )
    }
    assert_true(
      run_expr("\"" + name + "(NULL,1/0)\"")
      is Err({ kind: Scalar(ArithmeticFailure), .. }),
    )
    assert_true(
      run_expr("\"if(false," + name + "('x',-1),'safe')\"") is Ok(Text("safe")),
    )
    assert_true(
      run_expr("\"coalesce('safe'," + name + "('x',-1))\"") is Ok(Text("safe")),
    )
    guard run_expr("\"" + name + "(to_string(sqrt(-1)),1/0)\"") is Err(issue) else {
      fail("first child failure")
    }
    assert_true(
      @lower.expression_body(issue.expression) is @lower.Unary(@lower.Sqrt, _),
    )
  }
  for name in ["lpad", "rpad"] {
    for
      args in [
        "'abc',0,''", "'abc',2,''", "'abc',3,''", "'abc',4,''", "'',0,''",
      ] {
      assert_true(
        run_expr("\"" + name + "(" + args + ")\"")
        is Err({ kind: Scalar(InvalidOperand), .. }),
      )
    }
    for args in ["NULL,-1,''", "'abc',NULL,''", "'abc',-1,NULL"] {
      assert_true(run_expr("\"" + name + "(" + args + ")\"") is Ok(Null))
    }
    guard run_expr("\"" + name + "(NULL,-1,to_string(1/0))\"") is Err(issue) else {
      fail("later child failure")
    }
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
}

///|
fn pad_sides_expression(
  name : String,
  length : Int,
  pattern? : Bool = true,
) -> @lower.Expression {
  let body = "{\"" +
    name +
    "\":[{\"field\":\"payload\"},{\"literal\":" +
    length.to_string() +
    "}" +
    (if pattern { ",{\"literal\":\"💫x\"}" } else { "" }) +
    "]}"
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
fn pad_sides_frame(
  logical : LogicalBudget,
  workspace : RowWorkspace,
  name : String,
  length : Int,
  pattern? : Bool = true,
) -> ExpressionFrame {
  expression_frame(
    pad_sides_expression(name, length, pattern~),
    Map([("payload", Text(String::make(64, '😀')))]),
    [],
    { remaining: 100000, max_frames: 10, },
    workspace,
    Some(expression_roots(logical, 10)),
  ).unwrap()
}

///|
test "side slices and padding admit exact logical work live bytes and workspace before construction" {
  // All expectations follow the independently specified wire/weight formula:
  // input = (258 bytes,257 work), length=(2,1), optional pattern=(7,6).
  // Entry work=n+1; operands consumed twice; output weight charged once.
  // Many continuation slots=3*n+3; output storage uses exact UTF-16 units.
  for
    (name, length, pattern, work, live, slots, expected) in [
      ("left", 32, false, 648L, 390L, 73, String::make(32, '😀')),
      ("right", 32, false, 648L, 390L, 73, String::make(32, '😀')),
      ("lpad", 32, true, 661L, 397L, 76, String::make(32, '😀')),
      ("rpad", 32, true, 661L, 397L, 76, String::make(32, '😀')),
      (
        "lpad",
        96,
        false,
        808L,
        550L,
        169,
        String::make(32, ' ') + String::make(64, '😀'),
      ),
      (
        "rpad",
        96,
        false,
        808L,
        550L,
        169,
        String::make(64, '😀') + String::make(32, ' '),
      ),
      (
        "lpad",
        96,
        true,
        869L,
        605L,
        188,
        "💫x".repeat(16) + String::make(64, '😀'),
      ),
      (
        "rpad",
        96,
        true,
        869L,
        605L,
        188,
        String::make(64, '😀') + "💫x".repeat(16),
      ),
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
        let frame = pad_sides_frame(logical, workspace, name, length, pattern~)
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
              fail("exact " + name + " boundary")
            }
            assert_true(value.value is Text(actual) && actual == expected)
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
          _ => fail("resource selection")
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
test "padding cancels count locate size and build without refund or borrowed-root release" {
  for name in ["lpad", "rpad"] {
    for phase in 0..<4 {
      for exhaust in [false, true] {
        let logical = text_expression_budget(10000L, 10000L)
        let borrowed = retain_logical_value(
          logical,
          Text(String::make(64, '😀')),
        ).unwrap()
        let workspace = row_workspace(1000)
        assert_true(reserve_slots(workspace, 3))
        let frame = pad_sides_frame(logical, workspace, name, 96)
        let mut reached = false
        for _ in 0..<10000 {
          assert_true(advance_expression_frame(frame) is Ok(None))
          if frame.state is TextFunction(state) &&
            (if phase == 0 {
              state.substring_phase == 1 && state.position == 32
            } else if phase == 1 {
              state.substring_phase == 2 && state.position == 32
            } else if phase == 2 {
              state.substring_phase == 3 &&
              !state.building &&
              state.padding_remaining == 16L
            } else {
              state.building && state.padding_remaining == 16L
            }) {
            reached = true
            break
          }
        }
        assert_true(reached)
        let consumed = logical.work
        assert_true(consumed > 257L)
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
        release_logical_root(logical, borrowed).unwrap()
        release_slots(workspace, 3)
      }
    }
  }
}

///|
test "huge requested padding fails under admitted limits before an output buffer exists" {
  for name in ["lpad", "rpad"] {
    let owner = bound_pipeline(
      "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":\"" +
      name +
      "(payload,9007199254740991,'x')\"}}]",
    )
    let expression = @lower.lower_expression(owner, 1, 0, {
      max_nodes: 100,
      max_work: 10000,
      max_depth: 20,
      max_literal_nodes: 100,
      max_literal_text_bytes: 10000,
    }).unwrap()
    let logical = text_expression_budget(10000L, 1000L)
    let workspace = row_workspace(1000)
    let frame = expression_frame(
      expression,
      Map([("payload", Text("a"))]),
      [],
      { remaining: 100000, max_frames: 10, },
      workspace,
      Some(expression_roots(logical, 10)),
    ).unwrap()
    let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
    for _ in 0..<10000 {
      result = advance_expression_frame(frame)
      if frame.state is TextFunction(state) {
        assert_true(state.builder is None)
      }
      if !(result is Ok(None)) {
        break
      }
    }
    assert_true(result is Err({ kind: LogicalValue(LiveValueLimit), .. }))
    close_expression_frame(frame)
    assert_eq((logical.live, workspace.live), (0L, 0))
  }
}

///|
test "side slices cancel count locate size and build without leaking borrowed roots" {
  for name in ["left", "right"] {
    for phase in 0..<4 {
      for exhaust in [false, true] {
        let logical = text_expression_budget(10000L, 10000L)
        let borrowed = retain_logical_value(
          logical,
          Text(String::make(64, '😀')),
        ).unwrap()
        let workspace = row_workspace(1000)
        assert_true(reserve_slots(workspace, 3))
        let frame = pad_sides_frame(logical, workspace, name, 32, pattern=false)
        let mut reached = false
        for _ in 0..<10000 {
          assert_true(advance_expression_frame(frame) is Ok(None))
          if frame.state is TextFunction(state) &&
            (if phase == 0 {
              state.substring_phase == 1 && state.position == 32
            } else if phase == 1 {
              state.substring_phase == 2 && state.position == 32
            } else if phase == 2 {
              state.substring_phase == 3 && !state.building && state.units == 8
            } else {
              state.building && state.position == state.trim_start + 8
            }) {
            reached = true
            break
          }
        }
        assert_true(reached)
        let consumed = logical.work
        assert_true(consumed > 257L)
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
        release_logical_root(logical, borrowed).unwrap()
        release_slots(workspace, 3)
      }
    }
  }
}
