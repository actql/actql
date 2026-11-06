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

///|
test "bounded selected capacity funds exact completion metadata and preserves operation workspace" {
  let sequence = prepared_sequence(row_owner(",{\"select\":[\"a\"]}"))
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["select_1"],
    100000,
    10000,
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
      retained_entries: 10000,
      metadata_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 10000,
    max_frames: 100,
  }
  let measurement : FixedInputGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 100,
    max_nodes: 100,
    max_depth: 10,
  }
  let ordinary = generated_sequence_capacity(selected, limits, measurement).unwrap()
  let bounded = generated_bounded_sequence_capacity(
    selected, limits, measurement,
  ).unwrap()
  // One output field and one input identity, not a legacy whole-owner table.
  assert_eq(ordinary.retained_bytes - bounded.retained_bytes, 19998L * 256L)
  assert_eq(ordinary.execution_bytes - bounded.execution_bytes, 9998L * 256L)
  let more = { ..limits, rows: { ..limits.rows, operation_entries: 10001, }, }
  let larger = generated_bounded_sequence_capacity(selected, more, measurement).unwrap()
  assert_eq(larger.execution_bytes - bounded.execution_bytes, 256L)
  let fallback = generated_bounded_sequence_capacity(
    generated, limits, measurement,
  ).unwrap()
  let original = generated_sequence_capacity(generated, limits, measurement).unwrap()
  assert_eq(fallback.retained_bytes, original.retained_bytes)
  assert_eq(fallback.execution_bytes, original.execution_bytes)
}

///|
test "one original primitive Values constructor keeps logical budgets without phantom input copies" {
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(
      bound_pipeline(
        "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"n\":1,\"b\":true},{\"n\":null,\"b\":false}]},\"as\":\"out\"}]",
      ),
    ),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let values : ValueLimits = {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 10000,
  }
  let limits : SequenceExecutionLimits = {
    rows: {
      max_rows: 2,
      retained_entries: 100,
      metadata_entries: 100,
      operation_entries: 100,
      input_values: values,
      output_values: values,
    },
    max_work: 10000,
    max_frames: 16,
  }
  let measure : FixedInputGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 100,
    max_nodes: 100,
    max_depth: 10,
  }
  let selected = select_generated_sequence_step(generated, 0).unwrap()
  let whole = generated_bounded_sequence_capacity(generated, limits, measure).unwrap()
  let one = generated_bounded_sequence_capacity(selected, limits, measure).unwrap()
  assert_eq(whole.retained_bytes, one.retained_bytes)
  assert_eq(whole.execution_bytes, one.execution_bytes)
  let unused_measurement = {
    ..measure,
    max_nodes: 1000000,
    max_bytes: 1000000,
  }
  let larger = generated_bounded_sequence_capacity(
    generated, limits, unused_measurement,
  ).unwrap()
  assert_eq(larger.execution_bytes, whole.execution_bytes)
  let output = generated_bounded_sequence_capacity(
    generated,
    {
      ..limits,
      rows: { ..limits.rows, output_values: { ..values, max_nodes: 200, }, },
    },
    measure,
  ).unwrap()
  assert_true(output.retained_bytes > whole.retained_bytes)
  let tight = { ..values, max_nodes: 1, }
  assert_true(
    start_bounded_values(
      @bounded.control(),
      generated,
      2,
      tight,
      values,
      10000,
      16,
      100,
      100,
    )
    is Err(InputLimit),
  )
  let ordinary = generated_sequence_capacity(generated, limits, measure).unwrap()
  assert_true(ordinary.execution_bytes > whole.execution_bytes)
  // Text keeps the conservative constructor envelope; unused DATA must not
  // turn a non-primitive schema into this borrowed-scalar case.
  let text = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(
      bound_pipeline(
        "[{\"values\":{\"schema\":{\"t\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"t\":\"x\"}]},\"as\":\"out\"}]",
      ),
    ),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let text_small = generated_bounded_sequence_capacity(text, limits, measure).unwrap()
  let text_large = generated_bounded_sequence_capacity(
    text, limits, unused_measurement,
  ).unwrap()
  assert_true(text_large.execution_bytes > text_small.execution_bytes)
}
