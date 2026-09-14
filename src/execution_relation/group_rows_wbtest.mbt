///|
test "checked group count runs through generated sequence without expression contexts" {
  let sequence = prepared_sequence(
    bound_pipeline(
      "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":true},\"v\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[{\"k\":2,\"v\":null},{\"k\":null,\"v\":{\"literal\":\"x\"}},{\"k\":1,\"v\":null},{\"k\":2,\"v\":{\"literal\":\"x\"}},{\"k\":null,\"v\":null}]},\"as\":\"seed\"},{\"group\":{\"by\":[\"k\",\"k\"],\"aggregates\":{\"rows\":{\"fn\":\"count\"},\"present\":{\"fn\":\"count\",\"field\":\"v\"}}}}]",
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(result, Step(1)).unwrap())
  assert_eq(table.names, ["k", "present", "rows"])
  assert_eq(table.rows.length(), 3)
  assert_true(table.rows[0][0] is Null)
  assert_true(table.rows[0][1] is Number(1))
  assert_true(table.rows[0][2] is Number(2))
  assert_true(table.rows[1][0] is Number(1))
  assert_true(table.rows[1][1] is Number(0))
  assert_true(table.rows[1][2] is Number(1))
  assert_true(table.rows[2][0] is Number(2))
  assert_true(table.rows[2][1] is Number(1))
  assert_true(table.rows[2][2] is Number(2))
}

///|
test "empty global count publishes zero and feeds an independently completed consumer" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"group\":{\"by\":[],\"aggregates\":{\"a\":{\"fn\":\"count\"}}}}]",
  )
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let output = completed_output(result, Step(1)).unwrap()
  let table = test_row_output(output)
  assert_eq(table.names, ["a"])
  assert_eq(table.rows.length(), 1)
  assert_true(table.rows[0][0] is Number(0))
  let receiver = producer_consumer(owner, Step(1))
  let live = Ref(true)
  let binding = bind_live_completed_input(receiver, 0, owner, output, fn() {
    live.val
  }).unwrap()
  let downstream = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(
    downstream,
    [],
    { rows: run_limits(), max_work: 100000, max_frames: 100, },
    produced=[binding],
  ).unwrap()
  live.val = false
  assert_true(
    test_row_output(completed_output(completed, Step(0)).unwrap()).rows[0][0]
    is Number(0),
  )
  assert_true(
    execute_generated_sequence(
      downstream,
      [],
      { rows: run_limits(), max_work: 100000, max_frames: 100, },
      produced=[binding],
    )
    is Err(_),
  )
  // Zero input rows do not waive the independently enforced output limit.
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: { ..run_limits(), max_rows: 0, },
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(1, RowLimit)),
  )
}
