///|
fn direct_trig_unary_controls() -> Array[
  (@lower.UnaryOperator, String, Double, Double),
] {
  [
    (@lower.Sin, "sin", 0.0, 0.0),
    (@lower.Cos, "cos", 0.0, 1.0),
    (@lower.Tan, "tan", 0.0, 0.0),
    (@lower.Asin, "asin", 0.0, 0.0),
    (@lower.Acos, "acos", 1.0, 0.0),
    (@lower.Atan, "atan", 0.0, 0.0),
    (@lower.Sinh, "sinh", 0.0, 0.0),
    (@lower.Cosh, "cosh", 0.0, 1.0),
    (@lower.Tanh, "tanh", 0.0, 0.0),
    (@lower.Asinh, "asinh", 0.0, 0.0),
    (@lower.Acosh, "acosh", 1.0, 0.0),
    (@lower.Atanh, "atanh", 0.0, 0.0),
  ]
}

///|
fn direct_trig_exact(
  result : Result[Value, ScalarIssue],
  expected : Double,
) -> Unit raise {
  guard result is Ok(Number(actual)) else {
    fail("direct trig exact result missing")
  }
  assert_eq(actual.reinterpret_as_uint64(), expected.reinterpret_as_uint64())
}

///|
test "direct trig exact identities canonical zero and representable tiny odd results" {
  for (op, _, input, expected) in direct_trig_unary_controls() {
    direct_trig_exact(unary(op, Number(input)), expected)
    if input == 0.0 {
      direct_trig_exact(unary(op, Number(-0.0)), expected)
    }
  }
  // These exact tiny controls do not use the approximate oracle allowance.
  for
    op in [
      @lower.Sin,
      @lower.Tan,
      @lower.Asin,
      @lower.Atan,
      @lower.Sinh,
      @lower.Tanh,
      @lower.Asinh,
      @lower.Atanh,
    ] {
    for input in [5.0e-324, -5.0e-324] {
      direct_trig_exact(unary(op, Number(input)), input)
    }
  }
  for op in [@lower.Cos, @lower.Cosh] {
    for input in [5.0e-324, -5.0e-324] {
      direct_trig_exact(unary(op, Number(input)), 1.0)
    }
  }
  direct_trig_exact(unary(@lower.Tanh, Number(1.7976931348623157e308)), 1.0)
  direct_trig_exact(unary(@lower.Tanh, Number(-1.7976931348623157e308)), -1.0)
}

///|
test "direct trig atan2 preserves raw signed input quadrants before canonical output zero" {
  // Raw scalar inputs retain IEEE signs. Authored public -0 is rejected;
  // computed public operation results canonicalize zero before this boundary.
  for
    (first, second, expected) in [
      (0.0, 0.0, 0.0),
      (-0.0, 0.0, 0.0),
      (0.0, -0.0, 3.141592653589793),
      (-0.0, -0.0, -3.141592653589793),
      (0.0, -1.0, 3.141592653589793),
      (-0.0, -1.0, -3.141592653589793),
      (0.0, 1.0, 0.0),
      (-0.0, 1.0, 0.0),
      (1.0, 0.0, 1.5707963267948966),
      (-1.0, 0.0, -1.5707963267948966),
      (5.0e-324, 1.7976931348623157e308, 0.0),
      (-5.0e-324, 1.7976931348623157e308, 0.0),
    ] {
    direct_trig_exact(
      binary(@lower.Atan2, Number(first), Number(second)),
      expected,
    )
  }
}

///|
test "direct trig finite operand domains and immediate boundary failures" {
  for op in [@lower.Asin, @lower.Acos] {
    for value in [1.0000000000000002, -1.0000000000000002, 2.0, -2.0] {
      assert_true(unary(op, Number(value)) is Err(ArithmeticFailure))
    }
  }
  for value in [0.9999999999999999, 0.0, -0.0, -1.0, -1.7976931348623157e308] {
    assert_true(unary(@lower.Acosh, Number(value)) is Err(ArithmeticFailure))
  }
  for
    value in [
      1.0, -1.0, 1.0000000000000002, -1.0000000000000002, 1.7976931348623157e308,
      -1.7976931348623157e308,
    ] {
    assert_true(unary(@lower.Atanh, Number(value)) is Err(ArithmeticFailure))
  }
  // 710.4758600739439 is the preceding finite input (MPFR fixture); the
  // following binary64 value already overflows the rounded real result.
  for op in [@lower.Sinh, @lower.Cosh] {
    for
      value in [
        710.475860073944, -710.475860073944, 1.7976931348623157e308, -1.7976931348623157e308,
      ] {
      assert_true(unary(op, Number(value)) is Err(ArithmeticFailure))
    }
  }
  let inf = 1.7976931348623157e308 * 2.0
  let decimal = Captured(@admitted.decimal_from_coefficient("1", 1, 0).unwrap())
  for (op, _, _, _) in direct_trig_unary_controls() {
    assert_true(unary(op, Null) is Ok(Null))
    for
      value in [
        Text("1"),
        Boolean(true),
        decimal,
        Number(inf),
        Number(-inf),
        Number(inf - inf),
      ] {
      assert_true(unary(op, value) is Err(InvalidOperand))
    }
  }
  for
    (first, second) in [(Null, Number(1.0)), (Number(1.0), Null), (Null, Null)] {
    assert_true(binary(@lower.Atan2, first, second) is Ok(Null))
  }
  for
    value in [
      Text("1"),
      Boolean(true),
      decimal,
      Number(inf),
      Number(-inf),
      Number(inf - inf),
    ] {
    assert_true(binary(@lower.Atan2, value, Number(1.0)) is Err(InvalidOperand))
    assert_true(binary(@lower.Atan2, Number(1.0), value) is Err(InvalidOperand))
  }
}

///|
test "direct trig demanded child errors and lazy guards retain their original owners" {
  for (_, name, input, expected) in direct_trig_unary_controls() {
    for
      source in [
        name + "(1 / 0)",
        "safe_divide(" + name + "(1 / 0),0)",
        "greatest(NULL," + name + "(1 / 0))",
      ] {
      guard run_expr("\"" + source + "\"") is Err(issue) else {
        fail("direct trig suppressed child failure")
      }
      assert_true(issue.kind is Scalar(ArithmeticFailure))
      assert_true(
        @lower.expression_body(issue.expression)
        is @lower.Binary(@lower.Divide, _, _),
      )
    }
    for
      source in [
        "if(FALSE," + name + "(1 / 0),7)",
        "coalesce(7," + name + "(1 / 0))",
      ] {
      direct_trig_exact(
        run_expr("\"" + source + "\"").map_err(_ => InvalidOperand),
        7.0,
      )
    }
    direct_trig_exact(
      run_expr("\"" + name + "(if(TRUE," + input.to_string() + ",1 / 0))\"").map_err(_ => {
          InvalidOperand
        },
      ),
      expected,
    )
  }
  for
    source in [
      "atan2(NULL,1 / 0)", "atan2(1 / 0,NULL)", "atan2(1 / 0,sqrt(-1))", "safe_divide(atan2(NULL,1 / 0),0)",
    ] {
    guard run_expr("\"" + source + "\"") is Err(issue) else {
      fail("atan2 suppressed child failure")
    }
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  guard run_expr("\"atan2(sqrt(-1),1 / 0)\"") is Err(first) else {
    fail("atan2 first failure missing")
  }
  assert_true(
    @lower.expression_body(first.expression) is @lower.Unary(@lower.Sqrt, _),
  )
  assert_true(run_expr("\"if(FALSE,atan2(NULL,1 / 0),7)\"") is Ok(Number(7.0)))
  assert_true(run_expr("\"coalesce(7,atan2(1 / 0,NULL))\"") is Ok(Number(7.0)))
}

///|
test "direct trig shares exact unary and binary resource boundaries and releases roots" {
  let cases = direct_trig_unary_controls().map(fn(control) {
    let (_, name, input, expected) = control
    (
      "{\"" + name + "\":{\"literal\":" + input.to_string() + "}}",
      expected,
      4,
      5L,
      1L,
    )
  })
  cases.push(("{\"atan2\":[{\"literal\":0},{\"literal\":1}]}", 0.0, 6, 8L, 2L))
  for (source, expected, exact_control, exact_work, exact_live) in cases {
    let root = lowered(source)
    for
      (control, slots, work, live, success) in [
        (exact_control, 1, exact_work, exact_live, true),
        (exact_control - 1, 1, exact_work, exact_live, false),
        (exact_control, 0, exact_work, exact_live, false),
        (exact_control, 1, exact_work - 1L, exact_live, false),
        (exact_control, 1, exact_work, exact_live - 1L, false),
      ] {
      let logical = test_logical_budget(work, live)
      let workspace = row_workspace(slots)
      let result = evaluate_expression_retained(
        root,
        {},
        [],
        { remaining: control, max_frames: 1, },
        workspace,
        logical_work=Some(logical),
      )
      if success {
        let value = result.unwrap()
        assert_true(value.value is Number(_))
        direct_trig_exact(Ok(value.value), expected)
        assert_eq(
          (logical.work, logical.live, logical.peak, workspace.peak),
          (exact_work, 1L, exact_live, 1),
        )
        release_logical_root(logical, value.root.unwrap()).unwrap()
      } else if control < exact_control {
        assert_true(result is Err({ kind: ControlLimit, .. }))
      } else if slots < 1 {
        assert_true(result is Err({ kind: WorkspaceLimit, .. }))
      } else if work < exact_work {
        assert_true(
          result
          is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
        )
      } else {
        assert_true(result is Err({ kind: LogicalValue(LiveValueLimit), .. }))
      }
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
    assert_true(
      evaluate_expression(root, {}, [], {
        remaining: exact_control,
        max_frames: 0,
      })
      is Err({ kind: ControlLimit, .. }),
    )
  }
}

///|
test "direct trig evaluates each computed operand exactly once" {
  for (_, name, input, expected) in direct_trig_unary_controls() {
    let root = lowered(
      "{\"" +
      name +
      "\":{\"negate\":{\"negate\":{\"literal\":" +
      input.to_string() +
      "}}}}",
    )
    for work in [7, 8] {
      let workspace = row_workspace(3)
      let result = evaluate_expression_with_workspace(
        root,
        {},
        [],
        { remaining: work, max_frames: 3, },
        workspace,
      )
      if work == 8 {
        direct_trig_exact(result.map_err(_ => InvalidOperand), expected)
        assert_eq(workspace.peak, 3)
      } else {
        assert_true(result is Err({ kind: ControlLimit, .. }))
      }
      assert_eq(workspace.live, 0)
    }
  }
  let root = lowered(
    "{\"atan2\":[{\"negate\":{\"literal\":0}},{\"negate\":{\"literal\":-1}}]}",
  )
  for work in [9, 10] {
    let workspace = row_workspace(2)
    let result = evaluate_expression_with_workspace(
      root,
      {},
      [],
      { remaining: work, max_frames: 2, },
      workspace,
    )
    if work == 10 {
      direct_trig_exact(result.map_err(_ => InvalidOperand), 0.0)
    } else {
      assert_true(result is Err({ kind: ControlLimit, .. }))
    }
    assert_eq(workspace.live, 0)
  }
}

///|
test "direct trig cancellation retains borrowed custody and never refunds work" {
  let cases = direct_trig_unary_controls().map(fn(control) {
    let (_, name, input, _) = control
    ("{\"" + name + "\":{\"literal\":" + input.to_string() + "}}", 4)
  })
  cases.push(("{\"atan2\":[{\"literal\":0},{\"literal\":1}]}", 6))
  for (source, steps) in cases {
    for stop in 1..<steps {
      let logical = test_logical_budget(100L, 100L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(10)
      let frame = expression_frame(
        lowered(source),
        {},
        [],
        { remaining: 100, max_frames: 10, },
        workspace,
        Some(expression_roots(logical, 10)),
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
test "direct trig backend preparation checks branches without evaluating children" {
  let cases = direct_trig_unary_controls().map(fn(control) {
    let (_, name, _, _) = control
    name + "(1 / 0)"
  })
  cases.push("atan2(NULL,1 / 0)")
  for expression in cases {
    for source in [expression, "if(FALSE," + expression + ",7)"] {
      let request = capability_request(
        "[]",
        "{\"derive\":{\"value\":\"" + source + "\"}}",
      )
      let roots = @lower.fragment_pipeline_roots(
        @lower.fragment_request_pipeline(request),
      )
      assert_true(check_backend_capabilities(roots, 100) is Ok(_))
      assert_true(
        check_backend_capabilities(roots, 0)
        is Err({ kind: PreparationLimit, .. }),
      )
    }
  }
}
