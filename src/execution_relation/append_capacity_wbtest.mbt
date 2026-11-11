///|
test "bounded Append quote keeps original traversal without a measurement forest" {
  let sequence = prepared_sequence(
    bound_pipeline(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"source\"},{\"from\":\"source\",\"append\":{\"with\":\"source\"},\"as\":\"out\"}]",
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["append_1"],
    10000,
    1000,
  ).unwrap()
  let selected = select_generated_sequence_step(generated, 1).unwrap()
  let values : ValueLimits = {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 10000,
  }
  let limits : SequenceExecutionLimits = {
    rows: {
      max_rows: 3,
      retained_entries: 100,
      metadata_entries: 100,
      operation_entries: 1000,
      input_values: values,
      output_values: values,
    },
    max_work: 10000,
    max_frames: 100,
  }
  let measure : FixedInputGuardMeasureLimits = {
    max_work: 10000,
    max_nodes: 100,
    max_bytes: 100,
    max_depth: 10,
  }
  let large = { ..measure, max_nodes: 2830000, max_bytes: 10000000, }
  let original = generated_bounded_sequence_capacity(selected, limits, measure).unwrap()
  let enlarged = generated_bounded_sequence_capacity(selected, limits, large).unwrap()
  assert_eq(enlarged.retained_bytes, original.retained_bytes)
  assert_eq(enlarged.execution_bytes, original.execution_bytes)
  // A real additional workspace slot and output node remain funded.
  let workspace = generated_bounded_sequence_capacity(
    selected,
    { ..limits, rows: { ..limits.rows, operation_entries: 1001, }, },
    measure,
  ).unwrap()
  assert_eq(workspace.execution_bytes - original.execution_bytes, 256L)
  let output = generated_bounded_sequence_capacity(
    selected,
    {
      ..limits,
      rows: { ..limits.rows, output_values: { ..values, max_nodes: 101, }, },
    },
    measure,
  ).unwrap()
  assert_eq(output.retained_bytes - original.retained_bytes, 256L)
  assert_eq(output.execution_bytes - original.execution_bytes, 256L)
  for invalid in [{ ..measure, max_nodes: -1, }, { ..measure, max_bytes: -1, }] {
    assert_true(
      generated_bounded_sequence_capacity(selected, limits, invalid) is None,
    )
  }
  // The generic sequence still owns its separate physical measurement path.
  let generic = generated_sequence_capacity(generated, limits, measure).unwrap()
  let generic_large = generated_sequence_capacity(generated, limits, large).unwrap()
  assert_true(generic_large.execution_bytes > generic.execution_bytes)
}
