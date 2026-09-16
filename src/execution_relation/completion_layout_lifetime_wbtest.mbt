///|
test "common completed handoff preserves lifetime and independent results for rows and columns" {
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
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  let row_result = execute_generated_sequence(generated, [], limits).unwrap()
  let column_result = test_typed_completion(generated, 7)
  assert_true(
    completed_output(column_result, Step(1)).unwrap().table
    is Some(NumberTable(_)),
  )
  for result in [row_result, column_result] {
    let live = Ref(true)
    let output = restrict_completed_output(
      completed_output(result, Step(1)).unwrap(),
      () => live.val,
    )
    let receiver = typed_receiver(owner, "[{\"filter\":\"a > 0\"}]")
    let consumer_sequence = prepared_sequence(receiver)
    let consumer = prepare_generated_sequence(
      registered_relation_contracts(),
      consumer_sequence,
      [sequence_fragment_context(consumer_sequence, 0, 2L)],
      ["where_0"],
      100000,
      10000,
    ).unwrap()
    let binding = bind_completed_input(receiver, 0, owner, output).unwrap()
    let read = prepare_producer_read(receiver, binding, 1000, 10000).unwrap()
    let done = execute_generated_sequence(consumer, [], limits, produced=[
      binding,
    ]).unwrap()
    let independent = completed_output(done, Step(0)).unwrap()
    assert_eq(completed_row_count(independent), 2)
    assert_true(completed_cell(independent, 0, 0) is Some(Number(2)))
    assert_true(completed_cell(independent, 1, 0) is Some(Number(1)))
    live.val = false
    assert_false(producer_read_available(read))
    assert_true(prepare_producer_read(receiver, binding, 1000, 10000) is Err(_))
    assert_true(
      execute_generated_sequence(consumer, [], limits, produced=[binding])
      is Err(_),
    )
    assert_eq(completed_row_count(independent), 2)
    assert_true(completed_output(done, Step(0)) is Some(_))
    assert_true(completed_cell(independent, 0, 0) is Some(Number(2)))
  }
}
