///|
// Fixed IEEE-754 payloads independently select an existing operand. No runtime
// extrema, decimal formatting, or product comparator generated the expected bits.
test "number extrema retain exact finite neighbors subnormals and canonical zero" {
  for
    (a, b, minimum, maximum) in [
      (
        0x0000000000000001UL, 0x0000000000000002UL, 0x0000000000000001UL, 0x0000000000000002UL,
      ),
      (
        0x000fffffffffffffUL, 0x0010000000000000UL, 0x000fffffffffffffUL, 0x0010000000000000UL,
      ),
      (
        0x3fefffffffffffffUL, 0x3ff0000000000000UL, 0x3fefffffffffffffUL, 0x3ff0000000000000UL,
      ),
      (
        0x3ff0000000000000UL, 0x3ff0000000000001UL, 0x3ff0000000000000UL, 0x3ff0000000000001UL,
      ),
      (
        0x4330000000000000UL, 0x4330000000000001UL, 0x4330000000000000UL, 0x4330000000000001UL,
      ),
      (
        0x7feffffffffffffeUL, 0x7fefffffffffffffUL, 0x7feffffffffffffeUL, 0x7fefffffffffffffUL,
      ),
      (
        0x8000000000000001UL, 0x0000000000000001UL, 0x8000000000000001UL, 0x0000000000000001UL,
      ),
      (
        0xbff0000000000001UL, 0xbff0000000000000UL, 0xbff0000000000001UL, 0xbff0000000000000UL,
      ),
      (
        0xffefffffffffffffUL, 0x7fefffffffffffffUL, 0xffefffffffffffffUL, 0x7fefffffffffffffUL,
      ),
      (
        0x8000000000000000UL, 0x0000000000000000UL, 0x0000000000000000UL, 0x0000000000000000UL,
      ),
    ] {
    for (op, expected) in [(@lower.Greatest, maximum), (@lower.Least, minimum)] {
      for (first, second) in [(a, b), (b, a)] {
        let initial = number_extremum(
          op,
          Null,
          Number(first.reinterpret_as_double()),
          true,
        ).unwrap()
        guard number_extremum(
            op,
            initial,
            Number(second.reinterpret_as_double()),
            false,
          )
          is Ok(Number(actual)) else {
          fail("finite extrema refused")
        }
        assert_eq(actual.reinterpret_as_uint64(), expected)
      }
    }
  }
  for op in [@lower.Greatest, @lower.Least] {
    for
      bits in [
        0x0000000000000001UL, 0x0010000000000000UL, 0x4330000000000001UL, 0x7fefffffffffffffUL,
        0xffefffffffffffffUL,
      ] {
      guard number_extremum(
          op,
          Null,
          Number(bits.reinterpret_as_double()),
          true,
        )
        is Ok(Number(actual)) else {
        fail("singleton")
      }
      assert_eq(actual.reinterpret_as_uint64(), bits)
    }
    for
      invalid in [
        Number(1.0 / 0.0),
        Number(-1.0 / 0.0),
        Number(0.0 / 0.0),
        Text("1"),
        Boolean(true),
      ] {
      assert_true(
        number_extremum(op, Null, invalid, true) is Err(InvalidOperand),
      )
      assert_true(
        number_extremum(op, Null, invalid, false) is Err(InvalidOperand),
      )
    }
  }
}

///|
test "number extrema full roots preserve independently fixed finite values" {
  for
    (args, minimum, maximum) in [
      ("5e-324, 1e-323, 5e-324", 0x0000000000000001UL, 0x0000000000000002UL),
      ("-5e-324, 0, 5e-324", 0x8000000000000001UL, 0x0000000000000001UL),
      ("1, 1.0000000000000002", 0x3ff0000000000000UL, 0x3ff0000000000001UL),
      (
        "-1.7976931348623157e308, 1.7976931348623157e308", 0xffefffffffffffffUL,
        0x7fefffffffffffffUL,
      ),
      // Signed source zero normalizes to positive zero; canonical JSON Number
      // and Parameter values still reject negative zero.
      ("safe_negate(0), 0, safe_negate(0)", 0UL, 0UL),
    ] {
    for (name, expected) in [("greatest", maximum), ("least", minimum)] {
      guard run_expr("\"" + name + "(" + args + ")\"") is Ok(Number(actual)) else {
        fail("full extrema root")
      }
      assert_eq(actual.reinterpret_as_uint64(), expected)
    }
  }
}

///|
test "number extrema evaluate every demanded child in order while outer branches stay lazy" {
  for name in ["greatest", "least"] {
    for args in ["NULL", "NULL, NULL", "NULL, 7", "7, NULL", "1, NULL, 3"] {
      assert_true(run_expr("\"" + name + "(" + args + ")\"") is Ok(Null))
    }
    for (args, expected) in [("7", 7.0), ("7, 7, 7", 7.0)] {
      assert_true(
        run_expr("\"" + name + "(" + args + ")\"") is Ok(Number(actual)) &&
        actual == expected,
      )
    }
    for args in ["NULL, 1 / 0", "1 / 0, NULL", "7, NULL, 1 / 0"] {
      guard run_expr("\"" + name + "(" + args + ")\"") is Err(issue) else {
        fail("child failure suppressed")
      }
      assert_true(issue.kind is Scalar(ArithmeticFailure))
      assert_true(
        @lower.expression_body(issue.expression)
        is @lower.Binary(@lower.Divide, _, _),
      )
    }
    for args in ["sqrt(-1), 1 / 0", "NULL, sqrt(-1), 1 / 0"] {
      guard run_expr("\"" + name + "(" + args + ")\"") is Err(issue) else {
        fail("first failure missing")
      }
      assert_true(
        @lower.expression_body(issue.expression) is @lower.Unary(@lower.Sqrt, _),
      )
    }
    for
      source in [
        "if(FALSE, " + name + "(NULL, 1 / 0), 7)",
        "coalesce(7, " + name + "(NULL, 1 / 0))",
        "CASE WHEN TRUE THEN 7 ELSE " + name + "(NULL, 1 / 0) END",
        name + "(7, if(FALSE, 1 / 0, 7))",
      ] {
      assert_true(run_expr("\"" + source + "\"") is Ok(Number(7.0)))
    }
  }
}

///|
test "number extrema have exact linear logical control live and workspace ceilings" {
  for name in ["greatest", "least"] {
    for count in [1, 2, 257] {
      let source = "{\"" +
        name +
        "\":[" +
        Array::make(count, "{\"literal\":7}").join(",") +
        "]}"
      let root = lowered(source)
      // n+1 entries, n child results, n consumed operands, one result. Retained
      // accumulators are not new semantic results. Many copies n child views.
      let work = (3 * count + 2).to_int64()
      let control = 3 * count + 2
      let slots = count + 1
      let peak = if count == 1 { 1L } else { 2L }
      for failure in 0..<6 {
        let logical = test_logical_budget(
          if failure == 1 {
            work - 1L
          } else {
            work
          },
          if failure == 2 {
            peak - 1L
          } else {
            peak
          },
        )
        let workspace = row_workspace(
          if failure == 3 {
            slots - 1
          } else {
            slots
          },
        )
        let result = evaluate_expression_retained(
          root,
          {},
          [],
          {
            remaining: if failure == 4 {
              control - 1
            } else {
              control
            },
            max_frames: if failure == 5 {
              0
            } else {
              1
            },
          },
          workspace,
          logical_work=Some(logical),
        )
        match failure {
          0 => {
            guard result is Ok(value) else { fail("exact extrema bounds") }
            assert_true(value.value is Number(7.0))
            assert_eq(
              (logical.work, logical.live, logical.peak, workspace.peak),
              (work, 1L, peak, slots),
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
          _ => assert_true(result is Err({ kind: ControlLimit, .. }))
        }
        assert_eq((logical.live, workspace.live), (0L, 0))
      }
    }
  }
}

///|
test "number extrema strict NULL still pays every entry operand and result exactly once" {
  for name in ["greatest", "least"] {
    for position in [0, 128, 256] {
      let values = Array::make(257, "{\"literal\":7}")
      values[position] = "{\"literal\":null}"
      let root = lowered("{\"" + name + "\":[" + values.join(",") + "]}")
      // NULL and Number each have logical weight one; NULL wire has four bytes.
      let logical = test_logical_budget(773L, 5L)
      let workspace = row_workspace(258)
      let result = evaluate_expression_retained(
        root,
        {},
        [],
        { remaining: 773, max_frames: 1, },
        workspace,
        logical_work=Some(logical),
      ).unwrap()
      assert_true(result.value is Null)
      assert_eq(
        (logical.work, logical.live, logical.peak, workspace.peak),
        (773L, 4L, 5L, 258),
      )
      release_logical_root(logical, result.root.unwrap()).unwrap()
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}

///|
test "number extrema suspension draining and cancellation preserve custody and spent work" {
  for name in ["greatest", "least"] {
    let source = "\"" + name + "(7, NULL, 5, 3, 1)\""
    for quantum in [1, 7, 1000] {
      for drain in [false, true] {
        let logical = test_logical_budget(17L, 5L)
        let result = resume_test_expression(source, logical, quantum, drain~).unwrap()
        assert_true(result.value is Null)
        assert_eq((logical.work, logical.live, logical.peak), (17L, 4L, 5L))
        release_logical_root(logical, result.root.unwrap()).unwrap()
      }
    }
    // Two transitions per child plus Enter/Return; stop before terminal Return.
    for stop in 1..<12 {
      let logical = test_logical_budget(100L, 100L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(100)
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
      assert_false(borrowed.released)
      assert_eq((logical.work, logical.live, workspace.live), (spent, 1L, 0))
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
test "number extrema enforce per-value bytes even after a NULL operand" {
  for name in ["greatest", "least"] {
    for cap in [4L, 5L] {
      let logical = logical_budget(
        {
          max_input_rows: 1L,
          max_value_bytes: cap,
          max_live_value_bytes: 9L,
          max_work: 8L,
        },
        100,
        100,
        100,
      ).unwrap()
      let workspace = row_workspace(3)
      let result = evaluate_expression_retained(
        lowered("\"" + name + "(NULL, 10000)\""),
        {},
        [],
        { remaining: 8, max_frames: 1, },
        workspace,
        logical_work=Some(logical),
      )
      if cap == 5L {
        guard result is Ok(value) else { fail("exact per-value cap") }
        assert_true(value.value is Null)
        assert_eq((logical.work, logical.live, logical.peak), (8L, 4L, 9L))
        release_logical_root(logical, value.root.unwrap()).unwrap()
      } else {
        assert_true(
          result
          is Err({ kind: LogicalValue(ValueMeasure(WireMeasureFailure)), .. }),
        )
      }
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}
