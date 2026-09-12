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
    logical_entries=Some(logical),
  )
}

///|
test "actual evaluator charges demanded entry only along lazy selected branches" {
  for
    (source, count) in [
      ("\"if(TRUE, 7, 1 / 0)\"", 3L),
      ("\"CASE WHEN FALSE THEN 1 / 0 WHEN TRUE THEN 7 ELSE 1 / 0 END\"", 4L),
      ("\"coalesce(NULL, 7, 1 / 0)\"", 3L),
      ("\"-(1 + 2)\"", 4L),
      ("\"FALSE AND TRUE\"", 3L),
      ("\"TRUE OR FALSE\"", 3L),
    ] {
    let exact = test_logical_budget(count, 100L)
    assert_true(evaluate_entries(source, exact) is Ok(_))
    assert_eq(exact.work, count)
    let short = test_logical_budget(count - 1L, 100L)
    assert_true(
      evaluate_entries(source, short)
      is Err({ kind: LogicalEntry(WorkLimit), .. }),
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
  assert_eq(eager.work, 6L)
  let shared = test_logical_budget(5L, 100L)
  assert_true(evaluate_entries("\"1 + 2\"", shared) is Ok(_))
  assert_true(
    evaluate_entries("\"1 + 2\"", shared)
    is Err({ kind: LogicalEntry(WorkLimit), .. }),
  )
  assert_eq(shared.work, 5L)
  assert_true(
    evaluate_entries("\"7\"", shared)
    is Err({ kind: LogicalEntry(FailedLogicalBudget), .. }),
  )
}

///|
test "logical exhaustion retains the exact checked failing expression" {
  let expr = lowered("\"1 + 2\"")
  guard @lower.expression_body(expr) is @lower.Binary(_, _, right) else {
    fail("binary")
  }
  let budget = test_logical_budget(2L, 100L)
  let result = evaluate_expression_with_workspace(
    expr,
    Map([]),
    [],
    { remaining: 10000, max_frames: 100, },
    { limit: 10000, live: 0, peak: 0, },
    logical_entries=Some(budget),
  )
  guard result is Err(issue) else { fail("limit") }
  assert_true(physical_equal(issue.expression, right))
}
