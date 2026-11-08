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
  // The original immediate input cells are borrowed: no second 100-node,
  // 100-byte-text forest. Operation and measurement workspace stay prepaid.
  assert_eq(
    ordinary.execution_bytes - bounded.execution_bytes,
    9998L * 256L + 100L * 256L + 100L * 8L,
  )
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
  // Unused output ceilings do not allocate another forest of borrowed cells.
  assert_eq(output.retained_bytes, whole.retained_bytes)
  assert_eq(output.execution_bytes, whole.execution_bytes)
  let more_rows = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(
      bound_pipeline(
        "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[" +
        Array::make(4, "{\"n\":1,\"b\":true}").join(",") +
        "]},\"as\":\"out\"}]",
      ),
    ),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let rows_limits = { ..limits, rows: { ..limits.rows, max_rows: 4, }, }
  let before_rows = generated_bounded_sequence_capacity(
    generated, rows_limits, measure,
  ).unwrap()
  let after_rows = generated_bounded_sequence_capacity(
    more_rows, rows_limits, measure,
  ).unwrap()
  assert_true(after_rows.retained_bytes > before_rows.retained_bytes)
  assert_eq(
    after_rows.execution_bytes - before_rows.execution_bytes,
    after_rows.retained_bytes - before_rows.retained_bytes,
  )
  // The constructed output remains live during its cursor workspace. A
  // provider quote must round-trip through the existing canonical capacity
  // constructor even when output retention exceeds the small cursor frame.
  assert_true(
    execution_capacity(output.retained_bytes, output.execution_bytes) is Some(_),
  )
  assert_eq(
    output.execution_bytes - whole.execution_bytes,
    output.retained_bytes - whole.retained_bytes,
  )
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

///|
test "bounded immediate binding input borrows cells while copied schemas retain full allowance" {
  for
    (extra_schema, extra_row, immediate) in [
      ("", "", true),
      (
        ",\"payload\":{\"type\":\"string\",\"nullable\":false}", ",\"payload\":\"x\"",
        false,
      ),
      (
        ",\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        ",\"payload\":[1]", false,
      ),
    ] {
    let owner = bound_pipeline(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"flag\":{\"type\":\"boolean\",\"nullable\":false}" +
      extra_schema +
      "},\"rows\":[{\"id\":1,\"flag\":true" +
      extra_row +
      "}]},\"as\":\"seed\"},{\"from\":\"seed\",\"select\":[\"id\",\"flag\"]}]",
    )
    let sequence = prepared_sequence(owner)
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      [],
      ["select_1"],
      100000,
      10000,
    ).unwrap()
    let selected = select_generated_sequence_step(generated, 1).unwrap()
    let limits = compute_test_limits()
    let measure = managed_test_measure_limits()
    let more = {
      ..limits,
      rows: {
        ..limits.rows,
        input_values: {
          ..limits.rows.input_values,
          max_nodes: limits.rows.input_values.max_nodes + 1,
          max_text_bytes: limits.rows.input_values.max_text_bytes + 1,
        },
      },
    }
    let before = generated_bounded_sequence_capacity(selected, limits, measure).unwrap()
    let after = generated_bounded_sequence_capacity(selected, more, measure).unwrap()
    assert_eq(
      after.execution_bytes - before.execution_bytes,
      if immediate {
        0L
      } else {
        264L
      },
    )
    assert_eq(after.retained_bytes, before.retained_bytes)
    let old = generated_sequence_capacity(selected, limits, measure).unwrap()
    let old_more = generated_sequence_capacity(selected, more, measure).unwrap()
    assert_eq(old_more.execution_bytes - old.execution_bytes, 264L)
    let full = generated_bounded_sequence_capacity(generated, limits, measure).unwrap()
    let generic = generated_sequence_capacity(generated, limits, measure).unwrap()
    assert_eq(
      (full.retained_bytes, full.execution_bytes),
      (generic.retained_bytes, generic.execution_bytes),
    )
    let output_more = generated_bounded_sequence_capacity(
      selected,
      {
        ..limits,
        rows: {
          ..limits.rows,
          output_values: {
            ..limits.rows.output_values,
            max_nodes: limits.rows.output_values.max_nodes + 1,
          },
        },
      },
      measure,
    ).unwrap()
    assert_eq(output_more.retained_bytes - before.retained_bytes, 256L)
    assert_eq(output_more.execution_bytes - before.execution_bytes, 256L)
  }
}
