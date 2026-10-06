///|
fn test_logical_budget(work : Int64, live : Int64) -> LogicalBudget {
  logical_budget(
    {
      max_input_rows: 2L,
      max_value_bytes: 100L,
      max_live_value_bytes: live,
      max_work: work,
    },
    100,
    100,
    100,
  ).unwrap()
}

///|
test "logical budget spans rows bindings expressions and repeated operands" {
  let b = test_logical_budget(9L, 100L)
  admit_logical_rows(b, 2L).unwrap()
  assert_eq(b.work, 0L)
  // Input weight, row entry, binding entry, expression entry, operand weight,
  // produced weight, second row entry, binding entry, expression entry.
  let input = retain_logical_value(b, Number(7.0)).unwrap()
  charge_logical_work(b, 3L).unwrap()
  charge_logical_value(b, Number(7.0)).unwrap() |> ignore
  let output = retain_logical_value(b, Number(7.0)).unwrap()
  charge_logical_work(b, 3L).unwrap()
  assert_eq(b.work, 9L)
  assert_true(
    charge_logical_value(b, Number(7.0)) is Err(ValueMeasure(LogicalWorkLimit)),
  )
  release_logical_root(b, input).unwrap()
  release_logical_root(b, output).unwrap()
  assert_eq((b.live, b.work), (0L, 9L))
  assert_true(charge_logical_work(b, 0L) is Err(FailedLogicalBudget))
}

///|
test "aliases count separate live roots while transfer and release do not refund work" {
  // {"$json":{"x":1}} is 17 bytes per independently retained root.
  // The JSON domain wrapper does not add logical value work.
  let b = test_logical_budget(20L, 34L)
  let shared = logical_literal("{\"x\":1}")
  let first = retain_logical_value(b, shared).unwrap()
  let second = retain_logical_value(b, shared).unwrap()
  assert_eq((b.live, b.peak, b.work), (34L, 34L, 6L))
  let transferred = first
  release_logical_root(b, transferred).unwrap()
  assert_eq((b.live, b.work), (17L, 6L))
  let third = retain_logical_value(b, shared).unwrap()
  assert_eq((b.live, b.work), (34L, 9L))
  assert_true(retain_logical_value(b, shared) is Err(LiveValueLimit))
  assert_eq(b.live, 34L)
  release_logical_root(b, second).unwrap()
  release_logical_root(b, third).unwrap()
  assert_eq(b.live, 0L)
  assert_true(retain_logical_value(b, shared) is Err(FailedLogicalBudget))
}

///|
test "logical root cannot be released twice or into another budget" {
  let a = test_logical_budget(10L, 10L)
  let b = test_logical_budget(10L, 10L)
  let root = retain_logical_value(a, Null).unwrap()
  assert_true(release_logical_root(b, root) is Err(InvalidRootLifetime))
  assert_eq((a.live, b.live), (4L, 0L))
  release_logical_root(a, root).unwrap()
  assert_true(release_logical_root(a, root) is Err(InvalidRootLifetime))
  assert_eq(a.live, 0L)
}

///|
test "row admission and work enforce safe integer bounds including exact zero" {
  let zero = logical_budget(
    {
      max_input_rows: 0L,
      max_value_bytes: 0L,
      max_live_value_bytes: 0L,
      max_work: 0L,
    },
    0,
    0,
    0,
  ).unwrap()
  admit_logical_rows(zero, 0L).unwrap()
  charge_logical_work(zero, 0L).unwrap()
  assert_true(admit_logical_rows(zero, 1L) is Err(InputRowLimit))
  let max = test_logical_budget(9007199254740991L, 0L)
  charge_logical_work(max, 9007199254740991L).unwrap()
  assert_true(charge_logical_work(max, 1L) is Err(WorkLimit))
  let rows = test_logical_budget(10L, 10L)
  admit_logical_rows(rows, 1L).unwrap()
  admit_logical_rows(rows, 1L).unwrap()
  assert_true(admit_logical_rows(rows, 1L) is Err(InputRowLimit))
}
