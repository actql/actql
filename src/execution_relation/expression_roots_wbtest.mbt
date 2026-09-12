///|
fn retained_expression(
  source : String,
  b : LogicalBudget,
) -> Result[EvaluatedValue, EvalIssue] {
  evaluate_expression_retained(
    lowered(source),
    Map([]),
    [],
    { remaining: 10000, max_frames: 100, },
    { limit: 10000, live: 0, peak: 0, },
    logical_work=Some(b),
  )
}

///|
test "binary continuations retain only live operands and transfer the final root" {
  let b = test_logical_budget(100L, 3L)
  let result = retained_expression("\"1 + (2 + 3)\"", b).unwrap()
  assert_true(result.value is Number(6.0))
  assert_eq((b.live, b.peak), (1L, 3L))
  let lease = result.root.unwrap()
  assert_true(physical_equal(lease.owner, b))
  let before = b.work
  // Transfer to a future slot is just moving the same handle.
  let slot = lease
  assert_eq(b.live, 1L)
  release_logical_root(b, slot).unwrap()
  assert_eq((b.live, b.work), (0L, before))
  let short = test_logical_budget(100L, 2L)
  assert_true(
    retained_expression("\"1 + (2 + 3)\"", short)
    is Err({ kind: LogicalValue(LiveValueLimit), .. }),
  )
  assert_eq(short.live, 0L)
  assert_true(short.failed)
}

///|
test "condition roots die before the selected branch and forwarding adds no alias" {
  for
    source in [
      "\"if(TRUE, 'é', 'unused')\"", "\"CASE WHEN FALSE THEN 'unused' WHEN TRUE THEN 'é' ELSE 'unused' END\"",
      "\"coalesce(NULL, 'é', 'unused')\"",
    ] {
    // FALSE is five bytes; all other values in these examples fit in four.
    let cap = if source.contains("FALSE") { 5L } else { 4L }
    let b = test_logical_budget(100L, cap)
    let result = retained_expression(source, b).unwrap()
    assert_true(result.value is Text("é"))
    assert_eq(b.live, 4L)
    assert_eq(b.peak, cap)
    release_logical_root(b, result.root.unwrap()).unwrap()
    assert_eq(b.live, 0L)
  }
}

///|
test "failure cleans expression roots but never borrowed input roots" {
  let b = test_logical_budget(100L, 6L)
  let external = retain_logical_value(b, Null).unwrap()
  assert_true(
    retained_expression("\"1 + (2 + 3)\"", b)
    is Err({ kind: LogicalValue(LiveValueLimit), .. }),
  )
  assert_eq(b.live, 4L)
  assert_false(external.released)
  release_logical_root(b, external).unwrap()
  assert_eq(b.live, 0L)
  let failing = test_logical_budget(100L, 100L)
  assert_true(
    retained_expression("\"1 + (2 / 0)\"", failing)
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  assert_eq(failing.live, 0L)
  assert_true(failing.failed)
}

///|
test "boolean accumulator lifetime counts bytes without inventing semantic work" {
  let b = test_logical_budget(11L, 10L)
  let result = retained_expression("\"FALSE AND FALSE AND TRUE\"", b).unwrap()
  assert_true(result.value is Boolean(false))
  assert_eq((b.work, b.live, b.peak), (11L, 5L, 10L))
  release_logical_root(b, result.root.unwrap()).unwrap()
  let short = test_logical_budget(100L, 9L)
  assert_true(
    retained_expression("\"FALSE AND FALSE AND TRUE\"", short)
    is Err({ kind: LogicalValue(LiveValueLimit), .. }),
  )
  assert_eq(short.live, 0L)
}

///|
test "root scope reuses bounded slots and stale handles cannot release replacements" {
  let b = test_logical_budget(100L, 1L)
  let scope = expression_roots(b, 0)
  let first = track_expression_root(scope, Number(1.0), true).unwrap()
  release_expression_root(first).unwrap()
  for _ in 0..<20 {
    let lease = track_expression_root(scope, Number(1.0), true).unwrap()
    release_expression_root(lease).unwrap()
  }
  let last = track_expression_root(scope, Number(1.0), true).unwrap()
  assert_eq(scope.slots.length(), 1)
  assert_true(release_expression_root(first) is Err(InvalidRootLifetime))
  assert_eq(b.live, 1L)
  release_expression_root(last).unwrap()
  assert_eq(b.live, 0L)
}
