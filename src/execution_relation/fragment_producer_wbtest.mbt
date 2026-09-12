///|
test "checked fragments preserve completion evidence across producer and consumer" {
  let owner = row_owner(",{\"derive\":{\"c\":\"a + 10\"}}")
  let sequence = prepared_sequence(owner)
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    sequence,
    [],
    ["derive_1"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
    fragments=Some([sequence_fragment_context(sequence, 1, 2L)]),
  ).unwrap()
  let output = completed_output(upstream, Step(1)).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(owner)),
    Step(1),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"derive\":{\"d\":\"c + 1\"}},{\"filter\":\"d > 11\"},{\"select\":[\"d\"]}]",
    ),
    [("prior", @pipeline.ProducedInput(producer))],
    None,
    Some(input_cursor("\"prior\"")),
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
  let received_sequence = prepared_sequence(receiver)
  let contexts = [
    sequence_fragment_context(received_sequence, 0, 2L),
    sequence_fragment_context(received_sequence, 1, 2L),
  ]
  let bound = bind_completed_input(receiver, 0, owner, output).unwrap()
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    received_sequence,
    [],
    ["select_2"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
    produced=[bound],
    fragments=Some(contexts),
  ).unwrap()
  let delivered = completed_output(result, Step(2)).unwrap()
  assert_eq(delivered.table.names, ["d"])
  assert_eq(delivered.table.rows.length(), 1)
  assert_true(delivered.table.rows[0][0] is Number(12.0))
  assert_true(physical_equal(result.producer_inputs[0].output, output))
  // Correct values are not a substitute for the retained completion identity.
  let raw = capture_input(
    receiver,
    0,
    [
      input_cursor("{\"a\":1,\"b\":0,\"c\":11}"),
      input_cursor("{\"a\":0,\"b\":1,\"c\":10}"),
    ],
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      received_sequence,
      [raw],
      ["select_2"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some(contexts),
    )
    is Err(InputExecutionEvidencePending(0)),
  )
  let tight = [sequence_fragment_context(received_sequence, 0, 1L), contexts[1]]
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      received_sequence,
      [],
      ["select_2"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      produced=[bound],
      fragments=Some(tight),
    )
    is Err(Rows(0, LogicalRows(InputRowLimit))),
  )
  assert_eq(output.table.rows.length(), 2)
  assert_true(output.table.rows[0][2] is Number(11.0))
}
