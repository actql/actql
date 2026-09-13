///|
test "typed producer enforces actual parameter binding and requested target" {
  let (prepared, declarations) = ordered_parameter_preparation()
  let owner = bind_number(prepared, declarations, 3)
  let other = bind_number(prepared, declarations, 4)
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [
      ordered_sequence_fragment_context(sequence, 10000L),
      sequence_fragment_context(sequence, 2, 1L),
    ],
    ["derive_1", "select_3"],
    100000,
    10000,
  ).unwrap()
  let completion = test_typed_completion(generated, 1)
  let source = completed_output(completion, Step(1)).unwrap()
  assert_true(source.table is NumberTable(_))
  assert_true(completed_cell(source, 0, 0) is Some(Number(5)))
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  assert_true(
    bind_completed_input(receiver, 0, other, source)
    is Err(ProducerBindingMismatch),
  )
  assert_true(
    bind_completed_input(
      receiver,
      0,
      owner,
      completed_output(completion, Step(3)).unwrap(),
    )
    is Err(ProducerTargetMismatch),
  )
  let binding = bind_completed_input(receiver, 0, owner, source).unwrap()
  let consumer = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(
    consumer,
    [],
    { rows: run_limits(), max_work: 100000, max_frames: 100, },
    produced=[binding],
  ).unwrap()
  let output = completed_output(result, Step(0)).unwrap()
  assert_true(output.table is NumberTable(_))
  assert_true(completed_cell(output, 0, 0) is Some(Number(5)))
}

///|
test "typed producer cannot complete after a later row error or exhausted output budget" {
  let owner = row_owner(",{\"derive\":[{\"a\":\"1 / a\"}]}")
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [ordered_sequence_fragment_context(sequence, 1000L)],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  for width in [1, 7, 1000] {
    assert_true(
      try_typed_completion(generated, width, run_limits())
      is Err(Rows(1, Evaluation(1, 0, _))),
    )
  }
  let valid_owner = row_owner(",{\"derive\":[{\"a\":\"a + 1\"}]}")
  let valid_sequence = prepared_sequence(valid_owner)
  let valid = prepare_generated_sequence(
    registered_relation_contracts(),
    valid_sequence,
    [ordered_sequence_fragment_context(valid_sequence, 1000L)],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  let limits = run_limits()
  assert_true(
    try_typed_completion(valid, 7, {
      ..limits,
      output_values: { ..limits.output_values, max_nodes: 0, },
    })
    is Err(_),
  )
  assert_true(try_typed_completion(valid, 7, limits) is Ok(_))
}
