///|
test "abs executes independent finite binary64 expression vectors" {
  for
    (source, expected) in [
      ("abs(0)", 0.0),
      ("abs(1)", 1.0),
      ("abs(-9)", 9.0),
      ("abs(-0.25)", 0.25),
      ("abs(-2.25)", 2.25),
      ("abs(2)", 2.0),
      ("abs(-1e300)", 1.0e300),
      ("abs(-5e-324)", 5.0e-324),
    ] {
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Number(actual)) && actual == expected,
      msg=source,
    )
  }
}

///|
test "abs obeys independent exact bit boundaries and rejects foreign domains" {
  for
    (input, bits) in [
      (-0.0, 0UL),
      (0.0, 0UL),
      (-2.0, 0x4000000000000000UL),
      (2.0, 0x4000000000000000UL),
      (-3.5, 0x400c000000000000UL),
      (-5.0e-324, 1UL),
      (5.0e-324, 1UL),
      (-1.7976931348623157e308, 0x7fefffffffffffffUL),
      (1.7976931348623157e308, 0x7fefffffffffffffUL),
    ] {
    guard unary(@lower.Abs, Number(input)) is Ok(Number(value)) else {
      fail("finite abs input rejected")
    }
    assert_eq(value.reinterpret_as_uint64(), bits)
  }
  assert_true(unary(@lower.Abs, Null) is Ok(Null))
  for input in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(unary(@lower.Abs, Number(input)) is Err(ArithmeticFailure))
  }
  for value in [Boolean(true), Text("4")] {
    assert_true(unary(@lower.Abs, value) is Err(InvalidOperand))
  }
  let decimal = @admitted.decimal_from_coefficient("4", 8, 0).unwrap()
  assert_true(unary(@lower.Abs, Captured(decimal)) is Err(InvalidOperand))
}

///|
test "abs preserves NULL and selected branch demand" {
  assert_true(run_expr("\"abs(NULL)\"") is Ok(Null))
  assert_true(run_expr("\"if(FALSE, abs(1 / 0), 7)\"") is Ok(Number(7.0)))
  assert_true(run_expr("\"abs(-1)\"") is Ok(Number(1.0)))
  assert_true(
    run_expr("\"abs(1 / 0)\"") is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
}

///|
test "abs preserves the demanded failing expression owner" {
  guard run_expr("\"abs(1 / 0)\"") is Err(operand) else {
    fail("division operand must fail")
  }
  assert_true(
    @lower.expression_body(operand.expression)
    is @lower.Binary(@lower.Divide, _, _),
  )
}

///|
test "abs uses the existing exact unary control and workspace boundaries" {
  let root = lowered("{\"abs\":{\"literal\":9}}")
  for (work, slots, success) in [(4, 1, true), (3, 1, false), (4, 0, false)] {
    let workspace = row_workspace(slots)
    let actual = evaluate_expression_with_workspace(
      root,
      {},
      [],
      { remaining: work, max_frames: 1, },
      workspace,
    )
    if success {
      assert_true(actual is Ok(Number(9.0)))
      assert_eq(workspace.peak, 1)
    } else if work < 4 {
      assert_true(actual is Err({ kind: ControlLimit, .. }))
    } else {
      assert_true(actual is Err({ kind: WorkspaceLimit, .. }))
    }
    assert_eq(workspace.live, 0)
  }
  assert_true(
    evaluate_expression(root, {}, [], { remaining: 4, max_frames: 0, })
    is Err({ kind: ControlLimit, .. }),
  )
}

///|
test "abs enters and returns a computed operand exactly once" {
  let root = lowered("{\"abs\":{\"negate\":{\"literal\":9}}}")
  // Three expression nodes each enter and return once. The two nested unary
  // frames each retain one slot; no duplicated operand or synthetic IF exists.
  for work in [5, 6] {
    let workspace = row_workspace(2)
    let value = evaluate_expression_with_workspace(
      root,
      {},
      [],
      { remaining: work, max_frames: 2, },
      workspace,
    )
    if work == 6 {
      assert_true(value is Ok(Number(9.0)))
      assert_eq(workspace.peak, 2)
    } else {
      assert_true(value is Err({ kind: ControlLimit, .. }))
    }
    assert_eq(workspace.live, 0)
  }
}

///|
test "abs cancellation retains work and releases only owned roots" {
  for stop in [1, 2, 3] {
    let budget = test_logical_budget(10000L, 10000L)
    let borrowed = retain_logical_value(budget, Number(9)).unwrap()
    let workspace = row_workspace(100)
    let frame = expression_frame(
      lowered("{\"abs\":{\"literal\":9}}"),
      {},
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      Some(expression_roots(budget, 100)),
    ).unwrap()
    for _ in 0..<stop {
      assert_true(advance_expression_frame(frame).unwrap() is None)
    }
    let consumed = budget.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq(budget.work, consumed)
    assert_false(borrowed.released)
    assert_eq((budget.live, workspace.live), (borrowed.bytes, 0))
    release_logical_root(budget, borrowed).unwrap()
    assert_eq(budget.live, 0L)
  }
}

///|
test "abs has independent exact logical work and live root boundaries" {
  // Expression-only: three entries, three produced scalar weights and two
  // consumed operand weights = eight work units. Unary releases its child
  // before producing the next root: 9, -9, 9 occupy one, two, one bytes.
  let expr = lowered("{\"abs\":{\"negate\":{\"literal\":9}}}")
  for (work, live, failure) in [(8L, 2L, 0), (7L, 2L, 1), (8L, 1L, 2)] {
    let logical = test_logical_budget(work, live)
    let workspace = row_workspace(2)
    let result = evaluate_expression_retained(
      expr,
      {},
      [],
      { remaining: 100, max_frames: 2, },
      workspace,
      logical_work=Some(logical),
    )
    match failure {
      0 => {
        guard result is Ok(value) else {
          fail("exact ABS logical ceilings must succeed")
        }
        assert_true(value.value is Number(9.0))
        assert_eq((logical.work, logical.live, logical.peak), (8L, 1L, 2L))
        assert_false(logical.failed)
        release_logical_root(logical, value.root.unwrap()).unwrap()
        assert_eq(logical.work, 8L)
      }
      1 => {
        guard result is Err(issue) else {
          fail("one-short work ceiling must fail")
        }
        assert_true(issue.kind is LogicalValue(ValueMeasure(LogicalWorkLimit)))
        assert_true(
          @lower.expression_body(issue.expression)
          is @lower.Unary(@lower.Abs, _),
        )
        assert_eq((logical.work, logical.peak), (7L, 2L))
        assert_true(logical.failed)
      }
      2 => {
        guard result is Err(issue) else {
          fail("one-short live ceiling must fail")
        }
        assert_true(issue.kind is LogicalValue(LiveValueLimit))
        assert_true(
          @lower.expression_body(issue.expression)
          is @lower.Unary(@lower.Negate, _),
        )
        assert_eq((logical.work, logical.peak), (6L, 1L))
        assert_true(logical.failed)
      }
      _ => fail("unknown ABS logical boundary")
    }
    assert_eq((logical.live, workspace.live), (0L, 0))
    assert_eq(workspace.peak, 2)
  }
}
