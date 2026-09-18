///|
test "fixed append executes both produced input ports" {
  let producer_owner = row_owner("")
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(producer_owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let source = completed_output(upstream, Step(0)).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(producer_owner)),
    Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"l\",\"append\":{\"with\":\"r\"}}]"),
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
    ["append_0"],
    100000,
    10000,
  ).unwrap()
  let live = Ref(true)
  let inputs = [0, 1].map(index => {
    let bound = bind_live_completed_input(
      receiver,
      index,
      producer_owner,
      source,
      fn() { live.val },
    ).unwrap()
    prepare_producer_read(receiver, bound, 100, 100).unwrap()
  })
  let result = execute_fixed_producers_guarded(
    generated,
    inputs,
    Step(0),
    { rows: run_limits(), max_work: 100000, max_frames: 100, },
    max_rows=4,
    max_value_bytes=1,
    { max_work: 1000, max_bytes: 1000, max_nodes: 100, max_depth: 100, },
  ).unwrap()
  let output = completed_output(result, Step(0)).unwrap()
  assert_eq(completed_row_count(output), 4)
  for row in 0..<4 {
    let source_row = row % 2
    assert_true(
      completed_cell(output, row, 0) is Some(Number(value)) &&
      value == (if source_row == 0 { 1.0 } else { 0.0 }),
    )
    assert_true(
      completed_cell(output, row, 1) is Some(Number(value)) &&
      value == (if source_row == 0 { 0.0 } else { 1.0 }),
    )
  }
}
