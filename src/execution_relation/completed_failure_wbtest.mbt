///|
fn typed_receiver(
  owner : @lower.BoundPrepared,
  source : String,
  target? : @pipeline.Target = Step(1),
) -> @lower.BoundPrepared {
  let pipeline = @pipeline.check_with_evidence(
    input_cursor(source),
    [
      (
        "prior",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(owner)),
            target,
          ).unwrap(),
        ),
      ),
    ],
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
  @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "late row-conversion failure exposes no typed producer partial result" {
  let owner = row_owner(",{\"derive\":[{\"a\":\"a + 1\"}]}")
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [ordered_sequence_fragment_context(sequence, 1000L)],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  // The separate producer variable goes out of scope here. The output itself
  // must anchor both its completion and backing data for both consumers.
  let source = completed_output(test_typed_completion(generated, 1), Step(1)).unwrap()
  let failing = typed_receiver(
    owner, "[{\"filter\":\"if(a > 1, true, 1 / 0 > 0)\"},{\"select\":[\"a\"]}]",
  )
  let failing_sequence = prepared_sequence(failing)
  let consumer = prepare_generated_sequence(
    registered_relation_contracts(),
    failing_sequence,
    [sequence_fragment_context(failing_sequence, 0, 2L)],
    ["select_1"],
    100000,
    10000,
  ).unwrap()
  let bad_binding = bind_completed_input(failing, 0, owner, source).unwrap()
  let healthy = typed_receiver(owner, "[{\"select\":[\"a\"]}]")
  let good_binding = bind_completed_input(healthy, 0, owner, source).unwrap()
  let healthy_consumer = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(healthy),
    [],
    ["select_0"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  let before = execute_generated_sequence(healthy_consumer, [], limits, produced=[
    good_binding,
  ]).unwrap()
  for _attempt in 0..<2 {
    // Row zero is retained by the conversion builder before row one fails.
    // The failure is not retried by the typed adapter or published as success.
    assert_true(
      execute_generated_sequence(consumer, [], limits, produced=[bad_binding])
      is Err(Rows(0, Evaluation(1, 0, _))),
    )
    let after = execute_generated_sequence(healthy_consumer, [], limits, produced=[
      good_binding,
    ]).unwrap()
    for completion in [before, after] {
      let output = completed_output(completion, Step(0)).unwrap()
      assert_true(output.table is Some(NumberTable(_)))
      assert_true(completed_cell(output, 0, 0) is Some(Number(2)))
      assert_true(completed_cell(output, 1, 0) is Some(Number(1)))
    }
    assert_true(completed_cell(source, 0, 0) is Some(Number(2)))
  }
}

///|
test "typed producer conversion to row output is explicit bounded and repeatable" {
  let owner = row_owner(",{\"derive\":[{\"a\":\"a + 1\"}]}")
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [ordered_sequence_fragment_context(sequence, 1000L)],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  let source = completed_output(test_typed_completion(generated, 7), Step(1)).unwrap()
  let receiver = typed_receiver(owner, "[{\"filter\":\"a > 0\"}]")
  let consumer_sequence = prepared_sequence(receiver)
  let output_id = @lower.node_id(
    @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap(),
  )
  let consumer = prepare_generated_sequence(
    registered_relation_contracts(),
    consumer_sequence,
    [sequence_fragment_context(consumer_sequence, 0, 2L)],
    [output_id],
    100000,
    10000,
  ).unwrap()
  let binding = bind_completed_input(receiver, 0, owner, source).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  let tiny = { ..limits, rows: { ..limits.rows, operation_entries: 0, }, }
  assert_true(
    execute_generated_sequence(consumer, [], tiny, produced=[binding]) is Err(_),
  )
  for _attempt in 0..<2 {
    let result = execute_generated_sequence(consumer, [], limits, produced=[
      binding,
    ]).unwrap()
    let output = completed_output(result, Step(0)).unwrap()
    assert_true(source.table is Some(NumberTable(_)))
    assert_true(output.table is Some(RowTable(_)))
    assert_eq(completed_row_count(output), 2)
    assert_true(completed_cell(output, 0, 0) is Some(Number(2)))
    assert_true(completed_cell(output, 1, 0) is Some(Number(1)))
  }
}
