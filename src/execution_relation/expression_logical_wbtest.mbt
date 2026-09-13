///|
fn evaluate_entries(
  source : String,
  logical : LogicalBudget,
) -> Result[Value, EvalIssue] {
  evaluate_expression_with_workspace(
    lowered(source),
    Map([]),
    [],
    { remaining: 10000, max_frames: 100, },
    { limit: 10000, live: 0, peak: 0, },
    logical_work=Some(logical),
  )
}

///|
test "demanded root ceiling preserves failure position cleanup and existing logical charges" {
  let limits = test_logical_budget(1000L, 100L).limits
  let expr = lowered("\"1 > 123456789\"")
  guard @lower.expression_body(expr) is @lower.Binary(_, _, right) else {
    fail("comparison")
  }
  let constrained = logical_budget(
    limits,
    1000,
    1000,
    100,
    root_result_bytes=Some(8L),
    all_expression_roots=true,
  ).unwrap()
  let result = evaluate_expression_with_workspace(
    expr,
    Map([]),
    [],
    { remaining: 10000, max_frames: 100, },
    { limit: 10000, live: 0, peak: 0, },
    logical_work=Some(constrained),
  )
  guard result is Err(issue) else {
    fail("demanded literal must exceed ceiling")
  }
  assert_true(issue.kind is LogicalValue(ValueMeasure(WireMeasureFailure)))
  assert_true(physical_equal(issue.expression, right))
  assert_true(constrained.failed)
  assert_eq(constrained.live, 0L)
  let default_mode = logical_budget(
    limits,
    1000,
    1000,
    100,
    root_result_bytes=Some(8L),
  ).unwrap()
  assert_true(
    evaluate_entries("\"1 > 123456789\"", default_mode) is Ok(Boolean(false)),
  )
  let exact = logical_budget(
    limits,
    1000,
    1000,
    100,
    root_result_bytes=Some(9L),
    all_expression_roots=true,
  ).unwrap()
  assert_true(
    evaluate_entries("\"1 > 123456789\"", exact) is Ok(Boolean(false)),
  )
  assert_eq(exact.work, default_mode.work)
  assert_eq(exact.peak, default_mode.peak)
  assert_eq(exact.live, 0L)
}

///|
test "actual evaluator charges entry operand and production work along demanded branches" {
  for
    (source, count) in [
      ("\"if(TRUE, 7, 1 / 0)\"", 8L),
      ("\"CASE WHEN FALSE THEN 1 / 0 WHEN TRUE THEN 7 ELSE 1 / 0 END\"", 11L),
      ("\"coalesce(NULL, 7, 1 / 0)\"", 8L),
      ("\"-(1 + 2)\"", 11L),
      ("\"FALSE AND TRUE\"", 8L),
      ("\"TRUE OR FALSE\"", 8L),
    ] {
    let exact = test_logical_budget(count, 100L)
    assert_true(evaluate_entries(source, exact) is Ok(_))
    assert_eq(exact.work, count)
    let short = test_logical_budget(count - 1L, 100L)
    assert_true(
      evaluate_entries(source, short)
      is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
    )
    assert_true(short.failed)
  }
}

///|
test "eager boolean retains failure and sequential evaluations cannot reset logical work" {
  let eager = test_logical_budget(100L, 100L)
  assert_true(
    evaluate_entries("\"FALSE AND (1 / 0 > 0)\"", eager)
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  // and, false, gt, divide, 1, 0; failed divide never enters gt's RHS.
  assert_eq(eager.work, 12L)
  assert_true(eager.failed)
  let shared = test_logical_budget(15L, 100L)
  assert_true(evaluate_entries("\"1 + 2\"", shared) is Ok(_))
  assert_true(
    evaluate_entries("\"1 + 2\"", shared)
    is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
  )
  assert_eq(shared.work, 15L)
  assert_true(
    evaluate_entries("\"7\"", shared)
    is Err({ kind: LogicalEntry(FailedLogicalBudget), .. }),
  )
}

///|
test "value work charges full strings despite comparison short circuit and branch forwarding" {
  for
    (source, expected) in [
      ("\"'a' = 'bbbb'\"", 18L),
      ("\"coalesce(NULL, 'é')\"", 14L),
      ("\"if(TRUE, 'é', 'unused')\"", 14L),
      ("\"TRUE AND FALSE AND TRUE\"", 11L),
    ] {
    let b = test_logical_budget(expected, 100L)
    assert_true(evaluate_entries(source, b) is Ok(_))
    assert_eq(b.work, expected)
  }
}

///|
test "failed produced value limit does not publish a result or permit budget reuse" {
  let b = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 4L,
      max_live_value_bytes: 100L,
      max_work: 100L,
    },
    100,
    100,
    100,
  ).unwrap()
  assert_true(
    evaluate_entries("\"'aaaa'\"", b)
    is Err({ kind: LogicalValue(ValueMeasure(WireMeasureFailure)), .. }),
  )
  assert_true(
    evaluate_entries("\"7\"", b)
    is Err({ kind: LogicalEntry(FailedLogicalBudget), .. }),
  )
}

///|
test "logical exhaustion retains the exact checked failing expression" {
  let expr = lowered("\"1 + 2\"")
  guard @lower.expression_body(expr) is @lower.Binary(_, _, right) else {
    fail("binary")
  }
  let budget = test_logical_budget(3L, 100L)
  let result = evaluate_expression_with_workspace(
    expr,
    Map([]),
    [],
    { remaining: 10000, max_frames: 100, },
    { limit: 10000, live: 0, peak: 0, },
    logical_work=Some(budget),
  )
  guard result is Err(issue) else { fail("limit") }
  assert_true(physical_equal(issue.expression, right))
}
