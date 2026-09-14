///|
test "two fixed producer ports share storage but not admission or measurement credit" {
  let owner = row_owner("")
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let source = completed_output(upstream, Step(0)).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(owner)),
    Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"a\",\"right\":\"a\"}],\"select\":{\"l\":\"left.a\",\"r\":\"right.a\"}},\"from\":\"l\"}]",
    ),
    [
      ("l", @pipeline.ProducedInput(producer)),
      ("r", @pipeline.ProducedInput(producer)),
    ],
    None,
    None,
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let receiver = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["join_0"],
    100000,
    10000,
  ).unwrap()
  let live = Ref(true)
  let inputs = [0, 1].map(index => {
    let binding = bind_live_completed_input(receiver, index, owner, source, fn() {
      live.val
    }).unwrap()
    prepare_producer_read(receiver, binding, 100, 100).unwrap()
  })
  assert_eq(producer_read_input_index(inputs[0]), 0)
  assert_eq(producer_read_input_index(inputs[1]), 1)
  assert_true(
    physical_equal(inputs[0].bound.output.table, inputs[1].bound.output.table),
  )
  let execution = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  let measurement = {
    max_work: 1000,
    max_bytes: 1000,
    max_nodes: 12,
    max_depth: 100,
  }
  let result = execute_fixed_producers_guarded(
    generated,
    inputs,
    Step(0),
    execution,
    max_rows=2,
    max_value_bytes=1,
    measurement,
  ).unwrap()
  let output = completed_output(result, Step(0)).unwrap()
  assert_eq(completed_row_count(output), 2)
  for (row, expected) in [(0, 1.0), (1, 0.0)] {
    for column in 0..<2 {
      assert_true(
        completed_cell(output, row, column) is Some(Number(v)) && v == expected,
      )
    }
  }
  assert_true(
    execute_fixed_producer_inputs(generated, [inputs[1], inputs[0]], execution)
    is Err(InputSet),
  )
  assert_true(
    execute_fixed_producer_inputs(generated, [inputs[0], inputs[0]], execution)
    is Err(InputSet),
  )
  assert_true(
    execute_fixed_producer_inputs(generated, [inputs[0]], execution)
    is Err(InputSet),
  )
  assert_true(
    execute_fixed_producers_guarded(
      generated,
      inputs,
      Step(0),
      execution,
      max_rows=1,
      max_value_bytes=1,
      measurement,
    )
    is Err(InputRows),
  )
  // Eight input cells plus four output cells: shared backing is measured twice
  // at its two logical ports, and output does not get a fresh measurement ledger.
  assert_true(
    execute_fixed_producers_guarded(
      generated,
      inputs,
      Step(0),
      execution,
      max_rows=2,
      max_value_bytes=1,
      { ..measurement, max_nodes: 11, },
    )
    is Err(Measurement(Output, 1, 1, _)),
  )
  let buffer = prepare_admitted_output(receiver, Step(0), 2, {
    max_nodes: 10,
    max_text_bytes: 100,
    max_depth: 3,
    max_work: 100,
  }).unwrap()
  let output_schema = @pipeline.schema_at(checked, Step(0)).unwrap()
  for number in ["1", "0"] {
    append_admitted_output(
      buffer,
      Array::makei(2, column => {
        @admitted.admit(
          @schema.field_at(output_schema, column).unwrap().contract,
          input_cursor(number),
          { max_nodes: 1, max_text_bytes: 0, max_depth: 1, },
        ).unwrap()
      }),
    ).unwrap()
  }
  let received = finish_admitted_output(buffer).unwrap()
  let handles = inputs.copy()
  let pending = prepare_fixed_producer_measurement(
    handles,
    Step(0),
    max_rows=2,
    max_value_bytes=1,
    measurement,
  ).unwrap()
  handles[0] = inputs[1]
  let measured = finish_fixed_producer_measurement(pending, received).unwrap()
  assert_eq(fixed_producer_measurement_usage(measured).2, 12)
  assert_true(
    fixed_producer_measurement_matches(measured, inputs, received, 2, 1),
  )
  assert_false(
    fixed_producer_measurement_matches(measured, handles, received, 2, 1),
  )
  for wrong in [[inputs[0]], [inputs[1], inputs[0]], [inputs[0], inputs[0]]] {
    assert_true(
      prepare_fixed_producer_measurement(
        wrong,
        Step(0),
        max_rows=2,
        max_value_bytes=1,
        measurement,
      )
      is Err(ForeignInput),
    )
  }
  let short = prepare_fixed_producer_measurement(
    inputs,
    Step(0),
    max_rows=2,
    max_value_bytes=1,
    { ..measurement, max_nodes: 11, },
  ).unwrap()
  assert_true(
    finish_fixed_producer_measurement(short, received)
    is Err(Measurement(Output, 1, 1, _)),
  )
  assert_true(
    finish_fixed_producer_measurement(short, received) is Err(ForeignInput),
  )
  let unfinished = prepare_fixed_producer_measurement(
    inputs,
    Step(0),
    max_rows=2,
    max_value_bytes=1,
    measurement,
  ).unwrap()
  live.val = false
  assert_true(
    finish_fixed_producer_measurement(unfinished, received) is Err(ForeignInput),
  )
  assert_false(
    fixed_producer_measurement_matches(measured, inputs, received, 2, 1),
  )
  assert_true(
    execute_fixed_producers_guarded(
      generated,
      inputs,
      Step(0),
      execution,
      max_rows=2,
      max_value_bytes=1,
      measurement,
    )
    is Err(ForeignInput),
  )
  assert_true(completion_is_live(output.completion))
  assert_eq(completed_row_count(output), 2)
}
