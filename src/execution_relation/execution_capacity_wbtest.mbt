///|
test "selected sequence capacity charges only reachable fragment contexts" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"},{\"total\":\"old + a\"}]},{\"filter\":\"total > 1\"},{\"select\":[\"total\",\"a\"]}",
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [
      ordered_sequence_fragment_context(sequence, 84L),
      sequence_fragment_context(sequence, 2, 2L),
    ],
    ["select_3"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: {
      max_rows: 2,
      retained_entries: 1,
      metadata_entries: 2,
      operation_entries: 3,
      input_values: {
        max_nodes: 4,
        max_text_bytes: 5,
        max_depth: 1,
        max_work: 100,
      },
      output_values: {
        max_nodes: 6,
        max_text_bytes: 7,
        max_depth: 1,
        max_work: 100,
      },
    },
    max_work: 100,
    max_frames: 8,
  }
  let measurement : FixedInputGuardMeasureLimits = {
    max_work: 100,
    max_bytes: 11,
    max_nodes: 9,
    max_depth: 10,
  }
  // Fixed scratch: 42 node slots and 23 text bytes. A fragment adds its
  // own logical live-value allowance and the shared physical traversal cap.
  let scratch = 42L * 256L + 23L * 8L
  let traversal = 10100L * 256L + 100000L * 8L
  let retained = 9L * 256L + 7L * 8L
  let capacity = fn(value : GeneratedSequence) {
    generated_sequence_capacity(value, limits, measurement).unwrap()
  }
  assert_eq(capacity(generated).retained_bytes, retained)
  assert_eq(
    capacity(generated).execution_bytes,
    scratch + traversal + 10000L * 264L,
  )
  assert_eq(
    capacity(select_generated_sequence_step(generated, 0).unwrap()).execution_bytes,
    scratch,
  )
  assert_eq(
    capacity(select_generated_sequence_step(generated, 1).unwrap()).execution_bytes,
    scratch + traversal + 78L * 264L,
  )
  assert_eq(
    capacity(select_generated_sequence_step(generated, 2).unwrap()).execution_bytes,
    scratch + traversal + 10000L * 264L,
  )
  assert_eq(
    capacity(select_generated_sequence_step(generated, 3).unwrap()).execution_bytes,
    scratch,
  )
  assert_eq(
    capacity(select_generated_sequence_prefix(generated, 1).unwrap()).execution_bytes,
    scratch + traversal + 78L * 264L,
  )
  assert_eq(
    capacity(select_generated_sequence_range(generated, 2, 3).unwrap()).execution_bytes,
    scratch + traversal + 10000L * 264L,
  )
}
