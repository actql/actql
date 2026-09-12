///|
fn ordered_row_budget(
  work : Int64,
  live : Int64,
  bytes? : Int64 = 1000L,
) -> LogicalBudget {
  logical_budget(
    {
      max_input_rows: 2L,
      max_value_bytes: bytes,
      max_live_value_bytes: live,
      max_work: work,
    },
    10000,
    10000,
    100,
  ).unwrap()
}

///|
fn run_ordered_rows(
  owner : @lower.BoundPrepared,
  input : Table,
  b : LogicalBudget,
) -> Result[Table, RowIssue] {
  evaluate_rows_with_workspace(
    row_kernel(owner, 1),
    input,
    100,
    { remaining: 100000, max_frames: 100, },
    row_output(),
    { limit: 100000, live: 0, peak: 0, },
    ordered_budget=Some(b),
  )
}

///|
test "empty ordered input preserves output schema with exact zero logical caps" {
  let owner = row_owner(",{\"derive\":[{\"a\":\"a + 1\"},{\"x\":\"a + 10\"}]}")
  let input = { ..row_capture(owner), rows: [], }
  let b = logical_budget(
    {
      max_input_rows: 0L,
      max_value_bytes: 0L,
      max_live_value_bytes: 0L,
      max_work: 0L,
    },
    10000,
    10000,
    100,
  ).unwrap()
  let output = run_ordered_rows(owner, input, b).unwrap()
  assert_eq(output.names, ["a", "b", "x"])
  assert_eq(output.rows.length(), 0)
  assert_eq((b.work, b.live, b.rows), (0L, 0L, 0L))
  assert_false(b.failed)
}

///|
test "ordered row execution preserves snapshot slots shadow and full retained output" {
  let owner = row_owner(
    ",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"},{\"total\":\"old + a\"}]}",
  )
  let input = row_capture(owner)
  let b = ordered_row_budget(84L, 78L, bytes=31L)
  let output = run_ordered_rows(owner, input, b).unwrap()
  assert_eq(output.names, ["a", "b", "old", "total"])
  for (row, expected) in [(0, [2.0, 0.0, 1.0, 3.0]), (1, [1.0, 1.0, 0.0, 1.0])] {
    for col, n in expected {
      guard output.rows[row][col] is Number(actual) else { fail("number") }
      assert_eq(actual, n)
    }
  }
  // Inputs: 2*5 weight. Each row: 1 row + 3 bindings + 18 expression work
  // + 15 retained-row weight. Peak: first output(31)+second input(13)
  // +three slots(3)+second output(31).
  assert_eq((b.work, b.peak, b.live), (84L, 78L, 0L))
  assert_true(input.rows[0][0] is Number(1.0))
  assert_eq(input.names, ["a", "b"])
  for
    limited in [
      ordered_row_budget(83L, 78L),
      ordered_row_budget(84L, 77L),
      ordered_row_budget(84L, 78L, bytes=30L),
    ] {
    assert_true(run_ordered_rows(owner, input, limited) is Err(_))
    assert_eq(limited.live, 0L)
    assert_true(limited.failed)
  }
}

///|
test "ordered rows are row major and cleanup on a failing unused binding" {
  let owner = row_owner(
    ",{\"derive\":[{\"x\":\"1 / a\"},{\"discarded\":\"1 / b\"}]},{\"select\":[\"x\"]}",
  )
  let b = ordered_row_budget(1000L, 1000L)
  assert_true(
    run_ordered_rows(owner, row_capture(owner), b)
    is Err(Evaluation(0, 1, { kind: Scalar(ArithmeticFailure), .. })),
  )
  assert_eq(b.live, 0L)
  assert_true(b.failed)
}

///|
test "all input layouts are validated before ordered binding evaluation" {
  let owner = row_owner(",{\"derive\":[{\"x\":\"1 / b\"}]}")
  let input = row_capture(owner)
  let invalid = { ..input, rows: [input.rows[0], []], }
  let b = ordered_row_budget(1000L, 1000L)
  assert_true(run_ordered_rows(owner, invalid, b) is Err(InvalidRows))
  assert_eq(b.live, 0L)
  assert_eq(b.work, 5L) // first input only, no evaluation of its failing RHS
}

///|
test "ordered output composes with existing filter and select under the same owner" {
  let owner = row_owner(
    ",{\"derive\":[{\"a\":\"a + 1\"},{\"x\":\"a + 10\"}]},{\"filter\":\"x > 11\"},{\"select\":[\"x\",\"a\"]}",
  )
  let table = run_ordered_rows(
    owner,
    row_capture(owner),
    ordered_row_budget(1000L, 1000L),
  ).unwrap()
  let filtered = evaluate_rows(
    row_kernel(owner, 2),
    table,
    100,
    { remaining: 10000, max_frames: 100, },
    row_output(),
  ).unwrap()
  let selected = evaluate_rows(
    row_kernel(owner, 3),
    filtered,
    100,
    { remaining: 10000, max_frames: 100, },
    row_output(),
  ).unwrap()
  assert_eq(selected.names, ["x", "a"])
  assert_eq(selected.rows.length(), 1)
  assert_true(selected.rows[0][0] is Number(12.0))
  assert_true(selected.rows[0][1] is Number(2.0))
}
