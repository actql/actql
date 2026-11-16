///|
fn string_group_capacity_fixture(
  recursive? : Bool = false,
  fragment? : Bool = false,
  aggregate? : String = "{\"fn\":\"string_agg\",\"field\":\"payload\",\"order_by\":[{\"id\":\"asc\"}],\"delimiter\":\"|\",\"max_bytes\":4096}",
) -> GeneratedSequence raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"bucket\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"string\",\"nullable\":true}" +
    (if recursive {
      ",\"unused\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}"
    } else {
      ""
    }) +
    "},\"rows\":[{\"id\":1,\"bucket\":1,\"payload\":{\"literal\":\"x\"}" +
    (if recursive { ",\"unused\":{\"literal\":[1]}" } else { "" }) +
    "}]},\"as\":\"seed\"},{\"group\":{\"by\":[\"bucket\"],\"aggregates\":{\"value\":" +
    aggregate +
    "}}}]",
  )
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    if fragment {
      [sequence_fragment_context(sequence, 1, 3L)]
    } else {
      []
    },
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  select_generated_sequence_step(generated, 1).unwrap()
}

///|
test "ordered direct StringAgg removes only absent input and measurement construction" {
  let generated = string_group_capacity_fixture()
  guard generated_sequence_step_at(generated, 0) is Some(@lower.RowStep(kernel)) else {
    fail("original ordered StringAgg kernel missing")
  }
  assert_true(bounded_string_group_borrows_input(kernel))
  let values : ValueLimits = {
    max_nodes: 100,
    max_text_bytes: 5000,
    max_depth: 10,
    max_work: 100000,
  }
  let limits : SequenceExecutionLimits = {
    rows: {
      max_rows: 3,
      retained_entries: 100,
      metadata_entries: 100,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 100,
  }
  let measure : FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_nodes: 100,
    max_bytes: 5000,
    max_depth: 10,
  }
  let original = generated_bounded_sequence_capacity(generated, limits, measure).unwrap()
  let full = generated_sequence_capacity(generated, limits, measure).unwrap()
  assert_true(original.execution_bytes < full.execution_bytes)
  let enlarged = generated_bounded_sequence_capacity(
    generated,
    {
      ..limits,
      rows: {
        ..limits.rows,
        input_values: {
          ..values,
          max_nodes: 2830000,
          max_text_bytes: 10000000,
        },
      },
    },
    { ..measure, max_nodes: 2830000, max_bytes: 10000000, },
  ).unwrap()
  assert_eq(enlarged.retained_bytes, original.retained_bytes)
  assert_eq(enlarged.execution_bytes, original.execution_bytes)
  let workspace = generated_bounded_sequence_capacity(
    generated,
    { ..limits, rows: { ..limits.rows, operation_entries: 10001, }, },
    measure,
  ).unwrap()
  assert_eq(workspace.execution_bytes - original.execution_bytes, 256L)
  let output = generated_bounded_sequence_capacity(
    generated,
    {
      ..limits,
      rows: {
        ..limits.rows,
        output_values: { ..values, max_nodes: 101, max_text_bytes: 5001, },
      },
    },
    measure,
  ).unwrap()
  assert_eq(output.retained_bytes - original.retained_bytes, 264L)
  assert_eq(output.execution_bytes - original.execution_bytes, 264L)
}

///|
test "StringAgg recursive distinct and dynamic families retain their full constructor" {
  let values : ValueLimits = {
    max_nodes: 100,
    max_text_bytes: 5000,
    max_depth: 10,
    max_work: 100000,
  }
  let limits : SequenceExecutionLimits = {
    rows: {
      max_rows: 3,
      retained_entries: 100,
      metadata_entries: 100,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 100,
  }
  let measure : FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_nodes: 100,
    max_bytes: 5000,
    max_depth: 10,
  }
  for
    generated in [
      string_group_capacity_fixture(recursive=true),
      string_group_capacity_fixture(
        aggregate="{\"fn\":\"string_agg\",\"field\":\"payload\",\"order_by\":[{\"id\":\"asc\"}],\"distinct\":true,\"delimiter\":\"|\",\"max_bytes\":4096}",
      ),
      string_group_capacity_fixture(
        aggregate="{\"fn\":\"string_agg\",\"field\":\"payload\",\"filter\":\"id > 0\",\"order_by\":[{\"id\":\"asc\"}],\"delimiter\":\"|\",\"max_bytes\":4096}",
        fragment=true,
      ),
    ] {
    guard generated_sequence_step_at(generated, 0)
      is Some(@lower.RowStep(kernel)) else {
      fail("original refused StringAgg kernel missing")
    }
    assert_false(bounded_string_group_borrows_input(kernel))
    let bounded = generated_bounded_sequence_capacity(
      generated, limits, measure,
    ).unwrap()
    let full = generated_sequence_capacity(generated, limits, measure).unwrap()
    assert_eq(bounded.retained_bytes, full.retained_bytes)
    assert_eq(bounded.execution_bytes, full.execution_bytes)
  }
}
