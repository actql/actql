///|
// Independently authored finite-FLOAT64 examples and binary64 boundaries from
// GoogleSQL SAFE arithmetic. No host evaluator or live BigQuery oracle is used.
test "SAFE binary arithmetic catches only overflow and divide by zero" {
  for
    (op, ordinary, a, b) in [
      (
        @lower.SafeAdd,
        @lower.Add,
        1.7976931348623157e308,
        1.7976931348623157e308,
      ),
      (
        @lower.SafeSubtract,
        @lower.Subtract,
        -1.7976931348623157e308,
        1.7976931348623157e308,
      ),
      (@lower.SafeMultiply, @lower.Multiply, 1.7976931348623157e308, 2.0),
      (@lower.SafeDivide, @lower.Divide, 1.7976931348623157e308, 0.5),
      (@lower.SafeDivide, @lower.Divide, 1.0, 5.0e-324),
      (@lower.SafeDivide, @lower.Divide, 1.0, 0.0),
      (@lower.SafeDivide, @lower.Divide, 0.0, 0.0),
    ] {
    for sign in [1.0, -1.0] {
      assert_true(binary(op, Number(sign * a), Number(sign * b)) is Ok(Null))
      assert_true(
        binary(ordinary, Number(sign * a), Number(sign * b))
        is Err(ArithmeticFailure),
      )
    }
  }
}

///|
test "SAFE binary arithmetic preserves finite results subnormals underflow and positive zero" {
  for
    (op, a, b, expected) in [
      (@lower.SafeAdd, 5.0, 4.0, 9.0),
      (@lower.SafeSubtract, 5.0, 4.0, 1.0),
      (@lower.SafeMultiply, 20.0, 4.0, 80.0),
      (@lower.SafeDivide, 20.0, 4.0, 5.0),
      (@lower.SafeDivide, 0.0, 20.0, 0.0),
      (@lower.SafeDivide, 1.0, -2.0, -0.5),
      (@lower.SafeAdd, 1.7976931348623157e308, 0.0, 1.7976931348623157e308),
      (
        @lower.SafeSubtract,
        -1.7976931348623157e308,
        0.0,
        -1.7976931348623157e308,
      ),
      (
        @lower.SafeMultiply,
        1.7976931348623157e308,
        -1.0,
        -1.7976931348623157e308,
      ),
      (@lower.SafeDivide, 1.7976931348623157e308, 1.0, 1.7976931348623157e308),
      (@lower.SafeAdd, 9007199254740992.0, 1.0, 9007199254740992.0),
      (@lower.SafeAdd, 5.0e-324, 5.0e-324, 1.0e-323),
      (@lower.SafeSubtract, 1.0e-323, 5.0e-324, 5.0e-324),
      (@lower.SafeMultiply, 5.0e-324, 0.5, 0.0),
      (@lower.SafeMultiply, -5.0e-324, 0.5, 0.0),
      (@lower.SafeDivide, 5.0e-324, 2.0, 0.0),
      (@lower.SafeDivide, -5.0e-324, 2.0, 0.0),
      (@lower.SafeDivide, 2.2250738585072014e-308, 2.0, 1.1125369292536007e-308),
      (@lower.SafeAdd, -0.0, -0.0, 0.0),
      (@lower.SafeSubtract, -0.0, 0.0, 0.0),
      (@lower.SafeMultiply, -0.0, 2.0, 0.0),
      (@lower.SafeDivide, -0.0, 2.0, 0.0),
    ] {
    guard binary(op, Number(a), Number(b)) is Ok(Number(actual)) else {
      fail("finite SAFE result refused")
    }
    assert_eq(actual.reinterpret_as_uint64(), expected.reinterpret_as_uint64())
  }
}

///|
test "SAFE_NEGATE has no finite overflow and preserves strict numeric domain" {
  for
    (input, expected) in [
      (0.0, 0.0),
      (-0.0, 0.0),
      (1.0, -1.0),
      (-1.0, 1.0),
      (5.0e-324, -5.0e-324),
      (-5.0e-324, 5.0e-324),
      (1.7976931348623157e308, -1.7976931348623157e308),
      (-1.7976931348623157e308, 1.7976931348623157e308),
    ] {
    guard unary(@lower.SafeNegate, Number(input)) is Ok(Number(actual)) else {
      fail("finite SAFE_NEGATE rejected")
    }
    assert_eq(actual.reinterpret_as_uint64(), expected.reinterpret_as_uint64())
  }
  assert_true(unary(@lower.SafeNegate, Null) is Ok(Null))
  for
    value in [
      Number(0.0 / 0.0),
      Number(1.0 / 0.0),
      Number(-1.0 / 0.0),
      Text("1"),
      Boolean(true),
      Captured(@admitted.decimal_from_coefficient("1", 8, 0).unwrap()),
    ] {
    assert_true(unary(@lower.SafeNegate, value) is Err(InvalidOperand))
  }
}

///|
test "SAFE binary arithmetic preserves strict NULL and rejects nonfinite nonnumber operands" {
  for
    op in [
      @lower.SafeAdd,
      @lower.SafeSubtract,
      @lower.SafeMultiply,
      @lower.SafeDivide,
    ] {
    assert_true(binary(op, Null, Number(1)) is Ok(Null))
    assert_true(binary(op, Number(1), Null) is Ok(Null))
    assert_true(binary(op, Null, Null) is Ok(Null))
    for
      value in [
        Number(0.0 / 0.0),
        Number(1.0 / 0.0),
        Number(-1.0 / 0.0),
        Text("1"),
        Boolean(true),
        Captured(@admitted.decimal_from_coefficient("1", 8, 0).unwrap()),
      ] {
      assert_true(binary(op, value, Number(1)) is Err(InvalidOperand))
      assert_true(binary(op, Number(1), value) is Err(InvalidOperand))
    }
  }
}

///|
test "SAFE operations preserve child failures first-failure identity and lazy branches" {
  for name in ["safe_add", "safe_subtract", "safe_multiply", "safe_divide"] {
    for
      args in [
        "1 / 0, 1", "1, 1 / 0", "NULL, 1 / 0", "1 / 0, NULL", "1 / 0, sqrt(-1)",
      ] {
      let text = name + "(" + args + ")"
      guard run_expr("\"" + text + "\"") is Err(issue) else {
        fail("SAFE suppressed demanded child failure")
      }
      assert_true(issue.kind is Scalar(ArithmeticFailure))
      assert_true(
        @lower.expression_body(issue.expression)
        is @lower.Binary(@lower.Divide, _, _),
      )
      assert_true(run_expr("\"if(FALSE, " + text + ", 7)\"") is Ok(Number(7.0)))
      assert_true(run_expr("\"coalesce(7, " + text + ")\"") is Ok(Number(7.0)))
    }
    assert_true(run_expr("\"" + name + "(NULL, 1)\"") is Ok(Null))
    assert_true(run_expr("\"" + name + "(1, NULL)\"") is Ok(Null))
  }
  guard run_expr("\"safe_negate(1 / 0)\"") is Err(issue) else {
    fail("SAFE_NEGATE suppressed child failure")
  }
  assert_true(
    @lower.expression_body(issue.expression)
    is @lower.Binary(@lower.Divide, _, _),
  )
  assert_true(
    run_expr("\"if(FALSE, safe_negate(1 / 0), 7)\"") is Ok(Number(7.0)),
  )
  assert_true(run_expr("\"safe_divide(1, safe_subtract(1, 1))\"") is Ok(Null))
  assert_true(
    run_expr("\"coalesce(safe_multiply(1.7976931348623157e308, 2), 7)\"")
    is Ok(Number(7.0)),
  )
}

///|
test "SAFE binary operands are demanded once at exact control and workspace limits" {
  for
    (name, expected) in [
      ("safe_add", 10.0),
      ("safe_subtract", 8.0),
      ("safe_multiply", 9.0),
      ("safe_divide", 9.0),
    ] {
    let root = lowered("{\"" + name + "\":[{\"literal\":9},{\"literal\":1}]}")
    for (work, slots, success) in [(6, 1, true), (5, 1, false), (6, 0, false)] {
      let workspace = row_workspace(slots)
      let actual = evaluate_expression_with_workspace(
        root,
        {},
        [],
        { remaining: work, max_frames: 2, },
        workspace,
      )
      if success {
        assert_true(actual is Ok(Number(n)) && n == expected)
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
test "SAFE binary logical charges do not disappear when arithmetic returns NULL" {
  // Three entries + three produced scalar weights + two consumed operands = 8.
  // Numeric input roots overlap at two bytes; the NULL result needs four bytes.
  let root = lowered("\"safe_divide(1, 0)\"")
  for
    (work, live, success) in [(8L, 4L, true), (7L, 4L, false), (8L, 3L, false)] {
    let logical = test_logical_budget(work, live)
    let workspace = row_workspace(10)
    let result = evaluate_expression_retained(
      root,
      {},
      [],
      { remaining: 100, max_frames: 10, },
      workspace,
      logical_work=Some(logical),
    )
    if success {
      guard result is Ok(value) else { fail("exact SAFE NULL logical bounds") }
      assert_true(value.value is Null)
      assert_eq((logical.work, logical.live, logical.peak), (8L, 4L, 4L))
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

///|
test "SAFE cancellation retains charged work and borrowed custody before either operand completes" {
  for
    source in [
      "safe_divide(1, 0)", "safe_multiply(1.7976931348623157e308, 2)", "safe_add(1, 2)",
      "safe_subtract(1, 2)", "safe_negate(1)",
    ] {
    for stop in [1, 2, 3] {
      let logical = test_logical_budget(10000L, 10000L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(100)
      let frame = expression_frame(
        lowered("\"" + source + "\""),
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

///|
test "SAFE demanded child failures release temporary roots without consuming borrowed custody" {
  for
    source in [
      "safe_add(9, 1 / 0)", "safe_subtract(NULL, 1 / 0)", "safe_multiply(9, sqrt(-1))",
      "safe_divide(9, 1 / 0)", "safe_negate(1 / 0)",
    ] {
    let logical = test_logical_budget(1000L, 1000L)
    let borrowed = retain_logical_value(logical, Number(7)).unwrap()
    let workspace = row_workspace(100)
    let result = evaluate_expression_retained(
      lowered("\"" + source + "\""),
      {},
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      logical_work=Some(logical),
    )
    assert_true(result is Err({ kind: Scalar(ArithmeticFailure), .. }))
    assert_true(logical.failed)
    assert_true(logical.work > 1L)
    assert_eq((logical.live, workspace.live), (borrowed.bytes, 0))
    assert_false(borrowed.released)
    let spent = logical.work
    release_logical_root(logical, borrowed).unwrap()
    assert_eq((logical.work, logical.live), (spent, 0L))
  }
}

///|
test "SAFE stepped and drained execution keep exact outcomes work and failure locations" {
  for
    source in [
      "safe_divide(1, 0)", "safe_add(1.7976931348623157e308, 1.7976931348623157e308)",
      "safe_subtract(5, 4)", "safe_multiply(5.0e-324, 0.5)", "safe_negate(-1.7976931348623157e308)",
      "safe_divide(NULL, 1 / 0)", "if(FALSE, safe_multiply(1 / 0, 2), 7)",
    ] {
    for n in 0..<18 {
      for (work, control) in [(n.to_int64(), 1000), (1000L, n)] {
        let a = test_logical_budget(work, 100L)
        let b = test_logical_budget(work, 100L)
        let stepped = resume_test_expression(
          "\"" + source + "\"",
          a,
          1,
          max_control=control,
        )
        let drained = resume_test_expression(
          "\"" + source + "\"",
          b,
          7,
          drain=true,
          max_control=control,
        )
        match (stepped, drained) {
          (Ok(x), Ok(y)) => {
            match (x.value, y.value) {
              (Number(x), Number(y)) =>
                assert_eq(x.reinterpret_as_uint64(), y.reinterpret_as_uint64())
              (Null, Null) => ()
              _ => fail("different SAFE values")
            }
            release_logical_root(a, x.root.unwrap()).unwrap()
            release_logical_root(b, y.root.unwrap()).unwrap()
          }
          (Err(x), Err(y)) => {
            assert_eq(x.kind, y.kind)
            assert_eq(
              @lower.expression_location(x.expression).range,
              @lower.expression_location(y.expression).range,
            )
          }
          _ => fail("draining changed SAFE outcome")
        }
        assert_eq(
          (a.work, a.live, a.peak, a.failed),
          (b.work, b.live, b.peak, b.failed),
        )
        assert_eq(a.live, 0L)
      }
    }
  }
}
