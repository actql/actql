///|
test "contains ordinary evaluator retains exact scalar sequences and empty matches" {
  for
    (source, expected) in [
      ("contains('banana', 'ana')", true),
      ("contains('aaab', 'aab')", true),
      ("contains('abc', 'A')", false),
      ("contains('abc', 'x')", false),
      ("contains('abc', 'abcd')", false),
      ("contains('abc', '')", true),
      ("contains('', '')", true),
      ("contains('', 'a')", false),
      ("contains('😀x😀', 'x😀')", true),
      ("contains('é', 'é')", false),
      ("contains('é', 'é')", false),
      ("contains('😀éx', '́')", true),
    ] {
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Boolean(value)) && value == expected,
      msg=source,
    )
  }
}

///|
test "contains ordinary evaluator preserves strict NULL eager failures and canonical operands" {
  for args in ["NULL, 'a'", "'a', NULL", "NULL, NULL", "NULL, ''", "'', NULL"] {
    assert_true(run_expr("\"contains(" + args + ")\"") is Ok(Null))
  }
  for
    args in [
      "NULL, if(1 / 0 > 0, 'a', 'b')", "if(1 / 0 > 0, 'a', 'b'), NULL", "'', if(1 / 0 > 0, 'a', 'b')",
    ] {
    assert_true(
      run_expr("\"contains(" + args + ")\"")
      is Err({ kind: Scalar(ArithmeticFailure), .. }),
    )
    assert_true(
      run_expr("\"if(FALSE, contains(" + args + "), TRUE)\"")
      is Ok(Boolean(true)),
    )
  }
  let writer = @encode.writer(1000, 100, 10)
  @lower.emit_expression(borrowed_text_comparison("contains"), writer)
  assert_eq(
    @encode.finish(writer),
    "{\"body\":[{\"body\":\"left\",\"op\":\"field\"},{\"body\":\"right\",\"op\":\"field\"}],\"op\":\"contains\"}",
  )
}

///|
test "contains ordinary evaluator charges every repeated prefix comparison at exact control limits" {
  // Six expression transitions and left/right field names cost 15 units.
  // Equal strings need 256 comparisons. The absent repeated-prefix case
  // needs 128 candidates times 129 comparisons and one cannot-fit poll.
  for
    (input, needle, expected, exact) in [
      (String::make(256, 'a'), String::make(256, 'a'), true, 271),
      (String::make(256, 'a'), String::make(128, 'a') + "b", false, 16528),
    ] {
    for drain in [false, true] {
      for quantum in [1, 7, 256] {
        for short in [false, true] {
          let control = {
            remaining: exact - (if short { 1 } else { 0 }),
            max_frames: 10,
          }
          let workspace = row_workspace(2)
          let frame = expression_frame(
            borrowed_text_comparison("contains"),
            Map([("left", Text(input)), ("right", Text(needle))]),
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
              let searching = frame.state is TextFunction(_)
              result = advance_expression_frame(frame, drain~)
              polls += 1
              if !drain {
                assert_true(before - control.remaining <= 64)
                if searching && before > 0 {
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
              result is Ok(Some({ value: Boolean(actual), .. })) &&
              actual == expected,
            )
            assert_eq(control.remaining, 0)
          }
          assert_eq((workspace.peak, workspace.live), (2, 0))
          assert_true(frame.closed)
        }
      }
    }
  }
}

///|
test "contains ordinary evaluator keeps semantic work live bytes and workspace limits independent" {
  // Three entries, two produced Text weights (257), two consumed operands,
  // and one Boolean result give 1032 work. Input roots peak at 516 bytes.
  // A long operand's measurement under the parent slot peaks at 11 slots;
  // the search itself retains only its two fixed handles and no output buffer.
  for drain in [false, true] {
    for quantum in [1, 7, 256] {
      for
        (work, live, slots, failure) in [
          (1032L, 516L, 11, 0),
          (1031L, 516L, 11, 1),
          (1032L, 515L, 11, 2),
          (1032L, 516L, 10, 3),
        ] {
        let logical = text_expression_budget(work, live)
        let workspace = row_workspace(slots)
        let text = Text(String::make(256, 'a'))
        let frame = expression_frame(
          borrowed_text_comparison("contains"),
          Map([("left", text), ("right", text)]),
          [],
          { remaining: 10000, max_frames: 10, },
          workspace,
          Some(expression_roots(logical, 10)),
        ).unwrap()
        let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
        let mut polls = 0
        while result is Ok(None) && polls < 3000 {
          for _ in 0..<quantum {
            if frame.state is TextFunction(state) {
              assert_true(state.kind == TextContains)
              assert_eq(state.allocated, 0)
              assert_true(state.builder is None)
              assert_true(state.output_root is None)
              assert_eq(workspace.live, 2)
            }
            result = advance_expression_frame(frame, drain~)
            polls += 1
            if !(result is Ok(None)) {
              break
            }
          }
        }
        match failure {
          0 => {
            guard result is Ok(Some(value)) else {
              fail("CONTAINS exact logical boundary")
            }
            assert_true(value.value is Boolean(true))
            assert_eq(
              (logical.work, logical.peak, workspace.peak),
              (1032L, 516L, 11),
            )
            assert_eq(logical.live, 4L)
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
          _ => fail("unknown CONTAINS boundary")
        }
        close_expression_frame(frame)
        assert_eq((logical.live, workspace.live), (0L, 0))
      }
    }
  }
}

///|
test "contains ordinary evaluator cancellation preserves borrowed roots and workspace across restarts" {
  for restarted in [false, true] {
    let logical = text_expression_budget(10000L, 10000L)
    let borrowed = retain_logical_value(logical, Text("external")).unwrap()
    let workspace = row_workspace(30)
    assert_true(reserve_slots(workspace, 3))
    let frame = expression_frame(
      borrowed_text_comparison("contains"),
      Map([
        ("left", Text(String::make(256, 'a'))),
        ("right", Text(String::make(128, 'a') + "b")),
      ]),
      [],
      { remaining: 20000, max_frames: 10, },
      workspace,
      Some(expression_roots(logical, 10)),
    ).unwrap()
    let mut reached = false
    for _ in 0..<3000 {
      assert_true(advance_expression_frame(frame) is Ok(None))
      if frame.state is TextFunction(state) &&
        state.matched == 64 &&
        state.position == (if restarted { 1 } else { 0 }) {
        assert_true(state.kind == TextContains)
        assert_eq(state.count, if restarted { 1 } else { 0 })
        assert_eq(state.allocated, 0)
        assert_true(state.builder is None)
        assert_true(state.output_root is None)
        reached = true
        break
      }
    }
    assert_true(reached)
    assert_eq(workspace.live, 5)
    assert_eq(logical.live, borrowed.bytes + 258L + 131L)
    let work = logical.work
    let remaining = frame.budget.remaining
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq((logical.work, frame.budget.remaining), (work, remaining))
    assert_eq((logical.live, workspace.live), (borrowed.bytes, 3))
    assert_false(borrowed.released)
    assert_true(
      advance_expression_frame(frame) is Err({ kind: InvalidControlLimits, .. }),
    )
    release_logical_root(logical, borrowed).unwrap()
    release_slots(workspace, 3)
    assert_eq((logical.live, workspace.live), (0L, 0))
  }
}

///|
test "CONTAINS result byte limits charge the Boolean rather than a position Number" {
  for
    (left, right, expected, bytes) in [("", "", true, 4L), ("", "x", false, 5L)] {
    for short in [false, true] {
      let logical = logical_budget(
        {
          max_input_rows: 1L,
          max_value_bytes: bytes - (if short { 1L } else { 0L }),
          max_live_value_bytes: 100L,
          max_work: 1000L,
        },
        100,
        100,
        10,
      ).unwrap()
      let workspace = row_workspace(100)
      let result = evaluate_expression_retained(
        borrowed_text_comparison("contains"),
        Map([("left", Text(left)), ("right", Text(right))]),
        [],
        { remaining: 1000, max_frames: 10, },
        workspace,
        logical_work=Some(logical),
      )
      if short {
        guard result is Err(issue) else {
          fail("oversized Boolean was published")
        }
        assert_eq(issue.kind, LogicalValue(ValueMeasure(WireMeasureFailure)))
      } else {
        guard result is Ok(value) else {
          fail("Boolean output exact byte ceiling")
        }
        assert_true(value.value is Boolean(actual) && actual == expected)
        assert_eq(value.root.unwrap().bytes, bytes)
        release_logical_root(logical, value.root.unwrap()).unwrap()
      }
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}
