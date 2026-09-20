///|
fn asof_test_kernel(
  kind : String,
  direction : String,
) -> (@lower.BoundPrepared, @lower.PreparedAsOfJoin) raise {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"clock\":{\"type\":\"number\",\"nullable\":false}," +
    "\"key\":{\"type\":\"number\",\"nullable\":true}," +
    "\"value\":{\"type\":\"number\",\"nullable\":false}}"
  let row = "{\"id\":1,\"clock\":1,\"key\":1,\"value\":1}"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[" +
    row +
    "]},\"as\":\"l\"},{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[" +
    row +
    "]},\"as\":\"r\"},{\"from\":\"l\",\"asof_join\":{\"with\":\"r\",\"kind\":\"" +
    kind +
    "\",\"by\":[{\"left\":\"key\",\"right\":\"key\"}]," +
    "\"left_id\":\"id\",\"left_time\":\"clock\"," +
    "\"right_time\":\"clock\",\"direction\":\"" +
    direction +
    "\",\"tolerance\":3,\"right_tie_break\":[\"id\"]," +
    "\"select\":{\"id\":\"left.id\",\"value\":\"right.value\"}}}]",
  )
  guard @lower.sequence_step(prepared_sequence(owner), 2)
    is Some(@lower.AsOfJoinStep(kernel)) else {
    fail("as-of join kernel")
  }
  (owner, kernel)
}

///|
fn asof_left(
  owner : @lower.BoundPrepared,
  kernel : @lower.PreparedAsOfJoin,
) -> CompletedTable {
  RowTable({
    owner,
    id: @lower.asof_join_input(kernel, true),
    names: ["id", "clock", "key", "value"],
    rows: [
      [Number(2), Number(7), Number(1), Number(20)],
      [Number(1), Number(5), Number(1), Number(10)],
      [Number(3), Number(6), Null, Number(30)],
    ],
  })
}

///|
fn asof_right(
  owner : @lower.BoundPrepared,
  kernel : @lower.PreparedAsOfJoin,
) -> CompletedTable {
  RowTable({
    owner,
    id: @lower.asof_join_input(kernel, false),
    names: ["id", "clock", "key", "value"],
    rows: [
      [Number(11), Number(4), Number(1), Number(40)],
      [Number(12), Number(6), Number(1), Number(60)],
      [Number(13), Number(8), Number(1), Number(80)],
      [Number(14), Number(6), Null, Number(99)],
    ],
  })
}

///|
fn asof_evaluate(
  kind : String,
  direction : String,
) -> Result[Table, RowIssue] raise {
  let (owner, kernel) = asof_test_kernel(kind, direction)
  evaluate_asof_join_rows(
    kernel,
    asof_left(owner, kernel),
    asof_right(owner, kernel),
    20,
    12L,
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
    { limit: 10000, live: 0, peak: 0, },
  )
}

///|
test "as-of join selects every direction and orders by left clock identity" {
  assert_true(
    join_numeric_rows_equal(asof_evaluate("left", "backward").unwrap().rows, [
      [Number(1), Number(40)],
      [Number(3), Null],
      [Number(2), Number(60)],
    ]),
  )
  assert_true(
    join_numeric_rows_equal(asof_evaluate("left", "forward").unwrap().rows, [
      [Number(1), Number(60)],
      [Number(3), Null],
      [Number(2), Number(80)],
    ]),
  )
  assert_true(
    join_numeric_rows_equal(asof_evaluate("inner", "nearest").unwrap().rows, [
      [Number(1), Number(40)],
      [Number(2), Number(60)],
    ]),
  )
}

///|
test "as-of join requires exact search evidence in the sequence driver" {
  let (owner, _) = asof_test_kernel("left", "nearest")
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["asof_join_2"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  assert_true(
    execute_generated_sequence(generated, [], limits)
    is Err(Rows(2, InvalidRowLimits)),
  )
  let exact = constrain_generated_asof_search(generated, 2, 1L).unwrap()
  let completed = execute_generated_sequence(exact, [], limits).unwrap()
  assert_eq(
    test_row_output(completed_output(completed, Step(2)).unwrap()).rows.length(),
    1,
  )
}

///|
test "as-of join keeps search and output ceilings independent" {
  let (owner, kernel) = asof_test_kernel("left", "nearest")
  let evaluate = fn(
    search : Int64,
    output : (Int, Int64),
  ) -> Result[Table, RowIssue] {
    evaluate_asof_join_rows(
      kernel,
      asof_left(owner, kernel),
      asof_right(owner, kernel),
      20,
      search,
      { remaining: 100000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
      selected_ceiling=Some(output),
    )
  }
  assert_true(evaluate(11L, (2, 20L)) is Err(RowLimit))
  assert_true(evaluate(12L, (2, 2L)) is Err(RowLimit))
  assert_eq(evaluate(12L, (2, 20L)).unwrap().rows.length(), 3)
}

///|
test "as-of join validates all clocks and rejects unresolved top ties" {
  let (owner, kernel) = asof_test_kernel("inner", "nearest")
  let invalid = RowTable({
    owner,
    id: @lower.asof_join_input(kernel, false),
    names: ["id", "clock", "key", "value"],
    rows: [[Number(11), Number(1.5), Number(9), Number(40)]],
  })
  assert_true(
    evaluate_asof_join_rows(
      kernel,
      asof_left(owner, kernel),
      invalid,
      20,
      3L,
      { remaining: 100000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
    )
    is Err(InvalidRows),
  )
  let tied = RowTable({
    owner,
    id: @lower.asof_join_input(kernel, false),
    names: ["id", "clock", "key", "value"],
    rows: [
      [Number(11), Number(4), Number(1), Number(40)],
      [Number(11), Number(6), Number(1), Number(60)],
    ],
  })
  assert_true(
    evaluate_asof_join_rows(
      kernel,
      asof_left(owner, kernel),
      tied,
      20,
      6L,
      { remaining: 100000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
    )
    is Err(AsOfTopTie(1, 0, 1)),
  )
}
