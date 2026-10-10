///|
// Independent finite-FLOAT64 expectations authored from the GoogleSQL unary
// ROUND/TRUNC contracts. These are not live BigQuery results or host Math
// output. Positive zero is ActQL's existing common arithmetic requirement.
test "round and trunc preserve exact binary64 boundaries without host rounding" {
  for
    (input, rounded, truncated) in [
      (0.0, 0.0, 0.0),
      (0.49999999999999994, 0.0, 0.0),
      (0.5, 1.0, 0.0),
      (0.5000000000000001, 1.0, 0.0),
      (1.4999999999999998, 1.0, 1.0),
      (1.5, 2.0, 1.0),
      (1.5000000000000002, 2.0, 1.0),
      (2.3, 2.0, 2.0),
      (2.5, 3.0, 2.0),
      (2.8, 3.0, 2.0),
      (2251799813685248.5, 2251799813685249.0, 2251799813685248.0),
      (4503599627370495.5, 4503599627370496.0, 4503599627370495.0),
      (4503599627370496.0, 4503599627370496.0, 4503599627370496.0),
      (4503599627370497.0, 4503599627370497.0, 4503599627370497.0),
      (9007199254740991.0, 9007199254740991.0, 9007199254740991.0),
      (9007199254740992.0, 9007199254740992.0, 9007199254740992.0),
      (1.7976931348623157e308, 1.7976931348623157e308, 1.7976931348623157e308),
      (5.0e-324, 0.0, 0.0),
      (2.225073858507201e-308, 0.0, 0.0),
      (2.2250738585072014e-308, 0.0, 0.0),
    ] {
    for sign in [1.0, -1.0] {
      for
        (op, magnitude) in [(@lower.Round, rounded), (@lower.Trunc, truncated)] {
        let expected = if magnitude == 0.0 { 0.0 } else { sign * magnitude }
        guard unary(op, Number(sign * input)) is Ok(Number(actual)) else {
          fail("finite unary rounding rejected")
        }
        assert_eq(
          actual.reinterpret_as_uint64(),
          expected.reinterpret_as_uint64(),
        )
      }
    }
  }
}

///|
test "round and trunc preserve the finite numeric domain and strict NULL" {
  for op in [@lower.Round, @lower.Trunc] {
    assert_true(unary(op, Null) is Ok(Null))
    for input in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
      assert_true(unary(op, Number(input)) is Err(InvalidOperand))
    }
    for
      value in [
        Boolean(true),
        Text("2.5"),
        Text("猫😀"),
        Captured(@admitted.decimal_from_coefficient("25", 8, 1).unwrap()),
      ] {
      assert_true(unary(op, value) is Err(InvalidOperand))
    }
  }
}

///|
test "round and trunc keep common child failure identity and lazy demand" {
  for (name, expected) in [("round", -3.0), ("trunc", -2.0)] {
    assert_true(
      run_expr("\"" + name + "(-2.5)\"") is Ok(Number(actual)) &&
      actual == expected,
    )
    assert_true(run_expr("\"" + name + "(NULL)\"") is Ok(Null))
    assert_true(
      run_expr("\"if(FALSE, " + name + "(1 / 0), 7)\"") is Ok(Number(7.0)),
    )
    guard run_expr("\"" + name + "(1 / 0)\"") is Err(issue) else {
      fail("child failure suppressed")
    }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
}

///|
test "round and trunc demand the child once at exact control and workspace bounds" {
  for name in ["round", "trunc"] {
    let root = lowered("{\"" + name + "\":{\"negate\":{\"literal\":9}}}")
    // Three entered nodes and three completed values: six control steps;
    // the nested unary expression needs two simultaneous frame slots.
    for (work, slots, success) in [(6, 2, true), (5, 2, false), (6, 1, false)] {
      let workspace = row_workspace(slots)
      let actual = evaluate_expression_with_workspace(
        root,
        {},
        [],
        { remaining: work, max_frames: 2, },
        workspace,
      )
      if success {
        assert_true(actual is Ok(Number(-9.0)))
        assert_eq(workspace.peak, 2)
      } else if work < 6 {
        assert_true(actual is Err({ kind: ControlLimit, .. }))
      } else {
        assert_true(actual is Err({ kind: WorkspaceLimit, .. }))
      }
      assert_eq(workspace.live, 0)
    }
  }
}

///|
test "round and trunc keep exact logical work and release live roots" {
  // Three entries, three produced scalar weights and two consumed operands
  // are eight logical work. Both -9 intermediates have two canonical bytes.
  for name in ["round", "trunc"] {
    let root = lowered("{\"" + name + "\":{\"negate\":{\"literal\":9}}}")
    for
      (work, live, success) in [
        (8L, 2L, true),
        (7L, 2L, false),
        (8L, 1L, false),
      ] {
      let logical = test_logical_budget(work, live)
      let workspace = row_workspace(2)
      let result = evaluate_expression_retained(
        root,
        {},
        [],
        { remaining: 100, max_frames: 2, },
        workspace,
        logical_work=Some(logical),
      )
      if success {
        guard result is Ok(value) else { fail("exact unary rounding bounds") }
        assert_true(value.value is Number(-9.0))
        assert_eq((logical.work, logical.live, logical.peak), (8L, 2L, 2L))
        release_logical_root(logical, value.root.unwrap()).unwrap()
      } else if work < 8L {
        assert_true(
          result
          is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
        )
      } else {
        assert_true(result is Err({ kind: LogicalValue(LiveValueLimit), .. }))
      }
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}

///|
test "rounding cancellation retains work and borrowed root custody" {
  for name in ["round", "trunc"] {
    for stop in [1, 2, 3] {
      let logical = test_logical_budget(10000L, 10000L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(100)
      let frame = expression_frame(
        lowered("{\"" + name + "\":{\"literal\":9}}"),
        {},
        [],
        { remaining: 1000, max_frames: 100, },
        workspace,
        Some(expression_roots(logical, 100)),
      ).unwrap()
      for _ in 0..<stop {
        assert_true(advance_expression_frame(frame).unwrap() is None)
      }
      let spent = logical.work
      close_expression_frame(frame)
      close_expression_frame(frame)
      assert_eq(logical.work, spent)
      assert_false(borrowed.released)
      assert_eq((logical.live, workspace.live), (borrowed.bytes, 0))
      release_logical_root(logical, borrowed).unwrap()
      assert_eq(logical.live, 0L)
    }
  }
}
