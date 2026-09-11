///|
test "completed producer runs through receiving driver with fresh input accounting" {
  let owner = row_owner("")
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let output = completed_output(upstream, Step(0)).unwrap()
  let receiver = producer_consumer(owner, Step(0))
  let bound = bind_completed_input(receiver, 0, owner, output).unwrap()
  let inputs = [bound]
  let exact = {
    ..run_limits(),
    input_values: {
      max_nodes: 6,
      max_text_bytes: 4,
      max_depth: 2,
      max_work: 10,
    },
  }
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    exact,
    { remaining: 10000, max_frames: 100, },
    produced=inputs,
  ).unwrap()
  inputs.clear()
  assert_eq(result.producer_inputs.length(), 1)
  assert_true(physical_equal(result.producer_inputs[0], bound))
  let received = completed_output(result, Step(0)).unwrap()
  assert_eq(received.table.names, ["a"])
  assert_true(received.table.rows[0][0] is Number(1.0))
  assert_true(received.table.rows[1][0] is Number(0.0))
  assert_true(physical_equal(received.table.owner, receiver))
  for
    limited in [
      { ..exact, max_rows: 1, },
      { ..exact, input_values: { ..exact.input_values, max_nodes: 5, }, },
      { ..exact, input_values: { ..exact.input_values, max_text_bytes: 3, }, },
      { ..exact, input_values: { ..exact.input_values, max_work: 9, }, },
      { ..exact, input_values: { ..exact.input_values, max_depth: 1, }, },
    ] {
    assert_true(
      evaluate_sequence_components(
        registered_relation_contracts(),
        prepared_sequence(receiver),
        [],
        ["select_0"],
        limited,
        { remaining: 10000, max_frames: 100, },
        produced=[bound],
      )
      is Err(InputLimit),
    )
  }
  assert_eq(output.table.names, ["a", "b"])
  assert_true(output.table.rows[0][1] is Number(0.0))
  // A failure does not consume, alter or re-execute the upstream result.
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(receiver),
      [],
      ["select_0"],
      exact,
      { remaining: 10000, max_frames: 100, },
      produced=[bound],
    )
    is Ok(_),
  )
  let foreign_receiver = producer_consumer(owner, Step(0))
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(foreign_receiver),
      [],
      ["select_0"],
      run_limits(),
      { remaining: 10000, max_frames: 100, },
      produced=[bound],
    )
    is Err(InputOwnership),
  )
}

///|
test "raw and completed inputs share ordinal dispatch and cumulative budgets" {
  let owner = row_owner("")
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let receiver = producer_consumer(owner, Step(0), extra_input=true)
  let bound = bind_completed_input(
    receiver,
    0,
    owner,
    completed_output(upstream, Step(0)).unwrap(),
  ).unwrap()
  let raw = capture_input(
    receiver,
    1,
    [input_cursor("{\"a\":9,\"b\":8}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [raw],
    ["select_0", "input_1"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
    produced=[bound],
  ).unwrap()
  assert_true(
    completed_output(result, Input(1)).unwrap().table.rows[0][0] is Number(9.0),
  )
  assert_true(
    completed_output(result, Step(0)).unwrap().table.rows[0][0] is Number(1.0),
  )
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(receiver),
      [raw],
      ["select_0"],
      { ..run_limits(), max_rows: 2, },
      { remaining: 10000, max_frames: 100, },
      produced=[bound],
    )
    is Err(InputLimit),
  )
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(receiver),
      [],
      ["select_0"],
      run_limits(),
      { remaining: 10000, max_frames: 100, },
      produced=[bound, bound],
    )
    is Err(InputSet),
  )
}
