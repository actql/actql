///|
test "typed producer projection sort enforce cumulative value and retained ceilings" {
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
  let receiver = typed_receiver(
    owner, "[{\"select\":[\"a\"]},{\"sort\":[{\"a\":\"asc\"}]}]",
  )
  let consumer = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["sort_1"],
    100000,
    10000,
  ).unwrap()
  let binding = bind_completed_input(receiver, 0, owner, source).unwrap()
  assert_true(binding.projection is None)
  let run = fn(rows : SequenceRunLimits) {
    execute_generated_sequence(
      consumer,
      [],
      { rows, max_work: 100000, max_frames: 100, },
      produced=[binding],
    )
  }
  // Input: two row nodes + four scalar nodes + four one-byte field names.
  // Output: select and sort each retain two rows of one scalar + its name.
  // Retention peak: three routing slots + 18 input units + 10 projected units.
  let exact : SequenceRunLimits = {
    ..run_limits(),
    max_rows: 2,
    retained_entries: 31,
    operation_entries: 22,
    input_values: {
      max_nodes: 6,
      max_text_bytes: 4,
      max_depth: 2,
      max_work: 10,
    },
    output_values: {
      max_nodes: 8,
      max_text_bytes: 4,
      max_depth: 2,
      max_work: 12,
    },
  }
  for
    attempt in [
      { ..exact, max_rows: 1, },
      { ..exact, retained_entries: 30, },
      { ..exact, operation_entries: 21, },
      { ..exact, input_values: { ..exact.input_values, max_nodes: 5, }, },
      { ..exact, input_values: { ..exact.input_values, max_text_bytes: 3, }, },
      { ..exact, input_values: { ..exact.input_values, max_work: 9, }, },
      { ..exact, output_values: { ..exact.output_values, max_nodes: 7, }, },
      { ..exact, output_values: { ..exact.output_values, max_text_bytes: 3, }, },
      { ..exact, output_values: { ..exact.output_values, max_work: 11, }, },
    ] {
    assert_true(run(attempt) is Err(_))
    let result = run(exact).unwrap()
    guard result.store is PhysicalStore(store) else { fail("physical store") }
    assert_eq(store.workspace.peak, 31)
    assert_eq(store.workspace.live, 15)
    assert_true(store.tables[0] is None)
    assert_true(store.tables[1] is None)
    let output = completed_output(result, Step(1)).unwrap()
    assert_true(output.table is NumberTable(_))
    assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
    assert_true(completed_cell(output, 1, 0) is Some(Number(2)))
    assert_true(completed_cell(source, 0, 0) is Some(Number(2)))
  }
}
