///|
// Independently fixed finite-FLOAT64 values. The selected GoogleSQL C++
// reference (81c15b796138185c046aefe852321011fdf96615) corroborates these;
// no ActQL evaluator or live BigQuery execution supplied the expectations.
test "decimal rounding selects exact decimal ties and preserves binary64 neighbors" {
  for
    (input, digits, rounded, truncated) in [
      (1.235, 2.0, 1.24, 1.23),
      (1.005, 2.0, 1.0, 1.0),
      (1.0050000000000001, 2.0, 1.01, 1.0),
      (2.675, 2.0, 2.67, 2.67),
      (2.6750000000000003, 2.0, 2.68, 2.67),
      (0.3, 1.0, 0.3, 0.2),
      (0.30000000000000004, 1.0, 0.3, 0.3),
      (123.7, -1.0, 120.0, 120.0),
      (124.99999999999999, -1.0, 120.0, 120.0),
      (125.0, -1.0, 130.0, 120.0),
      (125.00000000000001, -1.0, 130.0, 120.0),
      (0.49999999999999994, 0.0, 0.0, 0.0),
      (4503599627370497.0, 0.0, 4503599627370497.0, 4503599627370497.0),
      (9007199254740991.0, 20.0, 9007199254740991.0, 9007199254740991.0),
      (
        1.7976931348623157e308, 1.0, 1.7976931348623157e308, 1.7976931348623157e308,
      ),
      (1.4e308, -308.0, 1.0e308, 1.0e308),
      (1.7976931348623157e308, -309.0, 0.0, 0.0),
      (5.0e-324, 323.0, 0.0, 0.0),
      (5.0e-324, 324.0, 5.0e-324, 5.0e-324),
      (1.0e-323, 323.0, 1.0e-323, 0.0),
      (
        2.2250738585072014e-308, 311.0, 2.2250000000000004e-308, 2.2250000000000004e-308,
      ),
    ] {
    for sign in [1.0, -1.0] {
      for
        (op, magnitude) in [
          (@lower.RoundAt, rounded),
          (@lower.TruncAt, truncated),
        ] {
        let expected = if magnitude == 0.0 { 0.0 } else { sign * magnitude }
        guard binary(op, Number(sign * input), Number(digits))
          is Ok(Number(actual)) else {
          fail("finite decimal rounding rejected")
        }
        assert_eq(
          actual.reinterpret_as_uint64(),
          expected.reinterpret_as_uint64(),
          msg="input=\{input}; n=\{digits}",
        )
      }
    }
  }
}

///|
test "decimal rounding validates precision and handles extremes before integer conversion" {
  for op in [@lower.RoundAt, @lower.TruncAt] {
    for value in [1.0, -1.0, 1.7976931348623157e308, 5.0e-324] {
      for
        huge in [
          2147483648.0, 9007199254740992.0, 1.0e100, 1.7976931348623157e308,
        ] {
        assert_true(
          binary(op, Number(value), Number(huge)) is Ok(Number(actual)) &&
          actual == value,
        )
        guard binary(op, Number(value), Number(-huge)) is Ok(Number(zero)) else {
          fail("large negative precision")
        }
        assert_eq(zero.reinterpret_as_uint64(), 0UL)
      }
    }
    for position in [0.1, -0.5, 1.5, -1.5] {
      assert_true(
        binary(op, Number(1.25), Number(position)) is Err(ArithmeticFailure),
      )
    }
    for invalid in [1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0] {
      assert_true(
        binary(op, Number(invalid), Number(2.0)) is Err(InvalidOperand),
      )
      assert_true(
        binary(op, Number(1.25), Number(invalid)) is Err(InvalidOperand),
      )
    }
    for
      position in [
        Text("2"),
        Boolean(true),
        Captured(@admitted.decimal_from_coefficient("2", 2, 0).unwrap()),
      ] {
      assert_true(binary(op, Number(1.25), position) is Err(InvalidOperand))
    }
    assert_true(binary(op, Null, Number(2.0)) is Ok(Null))
    assert_true(binary(op, Number(1.25), Null) is Ok(Null))
    assert_true(binary(op, Null, Null) is Ok(Null))
    guard binary(op, Number(-0.0), Number(-308.0)) is Ok(Number(zero)) else {
      fail("negative zero")
    }
    assert_eq(zero.reinterpret_as_uint64(), 0UL)
  }
  for sign in [1.0, -1.0] {
    assert_true(
      binary(
        @lower.RoundAt,
        Number(sign * 1.7976931348623157e308),
        Number(-308.0),
      )
      is Err(ArithmeticFailure),
    )
    assert_true(
      binary(
        @lower.TruncAt,
        Number(sign * 1.7976931348623157e308),
        Number(-308.0),
      )
      is Ok(Number(actual)) &&
      actual == sign * 1.0e308,
    )
  }
}

///|
test "precision rounding retains demanded children strict NULL and first failure identity" {
  for name in ["round", "trunc"] {
    assert_true(run_expr("\"" + name + "(NULL, 2)\"") is Ok(Null))
    assert_true(run_expr("\"" + name + "(1.25, NULL)\"") is Ok(Null))
    for args in ["NULL, 1 / 0", "1 / 0, NULL", "1.25, 1 / 0"] {
      guard run_expr("\"" + name + "(" + args + ")\"") is Err(issue) else {
        fail("child failure suppressed")
      }
      assert_true(issue.kind is Scalar(ArithmeticFailure))
      assert_true(
        @lower.expression_body(issue.expression)
        is @lower.Binary(@lower.Divide, _, _),
      )
    }
    guard run_expr("\"" + name + "(sqrt(-1), 1 / 0)\"") is Err(issue) else {
      fail("first failure missing")
    }
    assert_true(
      @lower.expression_body(issue.expression) is @lower.Unary(@lower.Sqrt, _),
    )
    assert_true(
      run_expr("\"if(FALSE, " + name + "(1.0e308, -308), 7)\"")
      is Ok(Number(7.0)),
    )
    assert_true(
      run_expr("\"coalesce(7, " + name + "(NULL, 1 / 0))\"") is Ok(Number(7.0)),
    )
  }
}

///|
test "precision rounding bounds control scratch and logical roots exactly" {
  for (name, expected) in [("round", 130.0), ("trunc", 120.0)] {
    let root = lowered(
      "{\"" + name + "\":[{\"literal\":125},{\"literal\":-1}]}",
    )
    // Five child/entry returns, seven numerical cursor polls and final Return.
    for
      (control, slots, logical_work, live, success) in [
        (13, 32, 8L, 5L, true),
        (12, 32, 8L, 5L, false),
        (13, 31, 8L, 5L, false),
        (13, 32, 7L, 5L, false),
        (13, 32, 8L, 4L, false),
      ] {
      let logical = test_logical_budget(logical_work, live)
      let workspace = row_workspace(slots)
      let result = evaluate_expression_retained(
        root,
        {},
        [],
        { remaining: control, max_frames: 2, },
        workspace,
        logical_work=Some(logical),
      )
      if success {
        guard result is Ok(value) else {
          fail("exact precision rounding bounds")
        }
        assert_true(value.value is Number(actual) && actual == expected)
        assert_eq(
          (logical.work, logical.live, logical.peak, workspace.peak),
          (8L, 3L, 5L, 32),
        )
        release_logical_root(logical, value.root.unwrap()).unwrap()
      } else if control < 13 {
        assert_true(result is Err({ kind: ControlLimit, .. }))
      } else if slots < 32 {
        assert_true(result is Err({ kind: WorkspaceLimit, .. }))
      } else if logical_work < 8L {
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
test "precision rounding cancellation releases cursor custody without refunding work" {
  for name in ["round", "trunc"] {
    // n=311 exercises all nine exponentiation polls and the subnormal finish.
    for stop in 1..<21 {
      let logical = test_logical_budget(10000L, 10000L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(100)
      let frame = expression_frame(
        lowered(
          "{\"" +
          name +
          "\":[{\"literal\":2.2250738585072014e-308},{\"literal\":311}]}",
        ),
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
// Modular midpoint counterexamples to the rejected exact-rational proxy.
// These fixed results were independently evaluated by the pinned Google C++
// implementation in both portable Dekker and FMA configurations.
test "precision rounding preserves the selected extended precision operation sequence" {
  for
    (op, input, digits, expected) in [
      (@lower.RoundAt, 0x4885617970e7e3bdUL, -26.0, 0x4885617970e7e3beUL),
      (@lower.RoundAt, 0x4885617970e7e3beUL, -26.0, 0x4885617970e7e3beUL),
      (@lower.TruncAt, 0x4885617970e7e3beUL, -26.0, 0x4885617970e7e3beUL),
      (@lower.TruncAt, 0x4875617970e7e3beUL, -25.0, 0x4875617970e7e3beUL),
      (@lower.TruncAt, 0x3e46c7dd19c9049aUL, 24.0, 0x3e46c7dd19c9049aUL),
      (@lower.TruncAt, 0x3dd98b8f10cee22fUL, 26.0, 0x3dd98b8f10cee22fUL),
      (@lower.TruncAt, 0x3e45ddd831ebbe54UL, 24.0, 0x3e45ddd831ebbe54UL),
      (@lower.RoundAt, 0x0010000000000000UL, 316.0, 0x00100000002e1a92UL),
      (@lower.TruncAt, 0x0010000000000000UL, 316.0, 0x000ffffffef94330UL),
      (@lower.RoundAt, 0x0010000000000000UL, 323.0, 0x000fffffffffffffUL),
      (@lower.TruncAt, 0x0010000000000000UL, 323.0, 0x000fffffffffffffUL),
      (@lower.TruncAt, 0x000fffffffffffffUL, 323.0, 0x000ffffffffffffdUL),
    ] {
    for sign in [0UL, 0x8000000000000000UL] {
      guard binary(
          op,
          Number((input | sign).reinterpret_as_double()),
          Number(digits),
        )
        is Ok(Number(actual)) else {
        fail("reference boundary rejected")
      }
      assert_eq(actual.reinterpret_as_uint64(), expected | sign)
    }
  }
}

///|
test "precision rounding poll grouping preserves exact budgets and terminal overflow cleanup" {
  for
    (name, input, digits, success) in [
      ("round", "2.2250738585072014e-308", "311", true),
      ("trunc", "2.2250738585072014e-308", "311", true),
      ("round", "1.7976931348623157e308", "-308", false),
    ] {
    let mut reference = (-1, -1, -1L)
    for quantum in [1, 2, 7, 64] {
      let logical = test_logical_budget(10000L, 10000L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(100)
      let frame = expression_frame(
        lowered(
          "{\"" +
          name +
          "\":[{\"literal\":" +
          input +
          "},{\"literal\":" +
          digits +
          "}]}",
        ),
        {},
        [],
        { remaining: 1000, max_frames: 100, },
        workspace,
        Some(expression_roots(logical, 100)),
      ).unwrap()
      let mut polls = 0
      let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
      while result is Ok(None) {
        for _ in 0..<quantum {
          let before = frame.budget.remaining
          result = advance_expression_frame(frame)
          assert_true(before - frame.budget.remaining <= 1)
          polls += 1
          if !(result is Ok(None)) {
            break
          }
        }
      }
      if success {
        guard result is Ok(Some(value)) else {
          fail("precision quantum result")
        }
        assert_true(
          value.value is Number(actual) && actual == 2.2250000000000004e-308,
        )
        release_logical_root(logical, value.root.unwrap()).unwrap()
      } else {
        assert_true(result is Err({ kind: Scalar(ArithmeticFailure), .. }))
      }
      let signature = (polls, frame.budget.remaining, logical.work)
      if reference.0 < 0 {
        reference = signature
      } else {
        assert_eq(signature, reference)
      }
      close_expression_frame(frame)
      close_expression_frame(frame)
      assert_eq(logical.work, signature.2)
      assert_false(borrowed.released)
      assert_eq((logical.live, workspace.live), (borrowed.bytes, 0))
      release_logical_root(logical, borrowed).unwrap()
    }
  }
}

///|
test "precision rounding fast paths and validation retain operand charges" {
  for name in ["round", "trunc"] {
    for
      (arguments, null_result, expected, succeeds) in [
        ("1.25, 0", false, 1.0, true),
        ("1.25, 324", false, 1.25, true),
        ("1.25, -309", false, 0.0, true),
        ("1.25, 1.0e20", false, 1.25, true),
        ("0, 311", false, 0.0, true),
        ("NULL, 1.5", true, 0.0, true),
        ("1.25, NULL", true, 0.0, true),
        ("1.25, 1.5", false, 0.0, false),
      ] {
      let logical = test_logical_budget(100L, 100L)
      let workspace = row_workspace(32)
      let result = evaluate_expression_retained(
        lowered("\"" + name + "(" + arguments + ")\""),
        {},
        [],
        { remaining: 7, max_frames: 2, },
        workspace,
        logical_work=Some(logical),
      )
      if succeeds {
        guard result is Ok(value) else { fail("bounded fast path") }
        if null_result {
          assert_true(value.value is Null)
        } else {
          assert_true(value.value is Number(actual) && actual == expected)
        }
        // Three entered nodes, two produced operands, two consumed operands,
        // and the final produced scalar. No-op or NULL cannot skip a charge.
        assert_eq(logical.work, 8L)
        release_logical_root(logical, value.root.unwrap()).unwrap()
      } else {
        assert_true(result is Err({ kind: Scalar(ArithmeticFailure), .. }))
        assert_eq(logical.work, 7L)
      }
      assert_eq(workspace.peak, 32)
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}
