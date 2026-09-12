///|
test "keyed distinct matches explicit projection and never returns omitted payload" {
  for explicit in [false, true] {
    let owner = bound_pipeline(
      "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":true},\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":[{\"k\":2,\"payload\":[1]},{\"k\":1,\"payload\":[2]},{\"k\":2,\"payload\":[3]},{\"k\":null,\"payload\":[]},{\"k\":null,\"payload\":[9]}]},\"as\":\"seed\"}" +
      (if explicit {
        ",{\"select\":[\"k\"]},{\"distinct\":true}"
      } else {
        ",{\"distinct\":[\"k\"]}"
      }) +
      ",{\"take\":{\"count\":1,\"offset\":1}}]",
    )
    let distinct_step = if explicit { 2 } else { 1 }
    let take_step = distinct_step + 1
    let sequence = prepared_sequence(owner)
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      [],
      [
        "distinct_" + distinct_step.to_string(),
        "limit_" + take_step.to_string(),
      ],
      100000,
      10000,
    ).unwrap()
    let limits : SequenceExecutionLimits = {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    }
    assert_true(
      execute_generated_sequence(generated, [], {
        ..limits,
        rows: { ..limits.rows, operation_entries: 1, },
      })
      is Err(_),
    )
    for _i = 0; _i < 2; _i = _i + 1 {
      let complete = execute_generated_sequence(generated, [], limits).unwrap()
      let table = completed_output(complete, Step(distinct_step)).unwrap().table
      assert_eq(table.names, ["k"])
      assert_eq(table.rows.length(), 3)
      assert_true(table.rows[0][0] is Number(2.0))
      assert_true(table.rows[1][0] is Number(1.0))
      assert_true(table.rows[2][0] is Null)
      assert_true(
        completed_output(complete, Step(take_step)).unwrap().table.rows[0][0]
        is Number(1.0),
      )
    }
  }
}

///|
test "keyed distinct follows authored projection order after shadow and rename" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":[{\"a\":\"a + 10\"}]},{\"rename\":{\"a\":\"x\"}},{\"distinct\":[\"b\",\"x\"]}",
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [ordered_sequence_fragment_context(sequence, 100000L)],
    ["distinct_3"],
    100000,
    10000,
  ).unwrap()
  let complete = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = completed_output(complete, Step(3)).unwrap().table
  assert_eq(table.names, ["b", "x"])
  assert_true(table.rows[0][0] is Number(0.0))
  assert_true(table.rows[0][1] is Number(11.0))
  assert_true(table.rows[1][0] is Number(1.0))
  assert_true(table.rows[1][1] is Number(10.0))
}
