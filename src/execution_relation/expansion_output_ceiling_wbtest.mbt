///|
test "checked unpivot ceiling binds the exact generated step" {
  let owner = unpivot_sequence_owner()
  let generated = unpivot_generated(owner)
  let input = capture_input(
    owner,
    0,
    [input_cursor("{\"id\":1,\"jan\":10,\"feb\":20}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  let exact = constrain_generated_expansion_output(generated, 0, 3L).unwrap()
  assert_eq(selected_step_ceiling(exact.expansion_ceilings, 0), Some(3L))
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  let result = execute_generated_sequence(exact, [input], limits).unwrap()
  assert_eq(completed_row_count(completed_output(result, Step(0)).unwrap()), 3)
  let short = constrain_generated_expansion_output(exact, 0, 2L).unwrap()
  let cannot_weaken = constrain_generated_expansion_output(short, 0, 100L).unwrap()
  assert_eq(
    selected_step_ceiling(cannot_weaken.expansion_ceilings, 0),
    Some(2L),
  )
  assert_true(
    execute_generated_sequence(cannot_weaken, [input], limits)
    is Err(Rows(0, RowLimit)),
  )
  assert_true(
    constrain_generated_expansion_output(generated, -1, 1L) is Err(InputSet),
  )
  assert_true(
    constrain_generated_expansion_output(generated, 0, -1L)
    is Err(InvalidLimits),
  )
}

///|
test "checked unnest ceiling rejects excess output without narrowing input" {
  let owner = unnest_sequence_owner(
    "{\"column\":\"items\",\"as\":\"item\",\"outer\":true}",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["unnest_0"],
    100000,
    10000,
  ).unwrap()
  let input = capture_input(
    owner,
    0,
    [input_cursor("{\"id\":1,\"items\":[2,null]}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  let exact = constrain_generated_expansion_output(generated, 0, 2L).unwrap()
  let result = execute_generated_sequence(exact, [input], limits).unwrap()
  assert_eq(completed_row_count(completed_output(result, Step(0)).unwrap()), 2)
  let short = constrain_generated_expansion_output(generated, 0, 1L).unwrap()
  assert_true(
    execute_generated_sequence(short, [input], limits) is Err(Rows(0, RowLimit)),
  )
}
