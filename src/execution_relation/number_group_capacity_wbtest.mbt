///|
fn number_group_capacity_fixture(
  recursive : Bool,
  aggregate : String,
) -> GeneratedSequence raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"bucket\":{\"type\":\"string\",\"nullable\":false},\"n\":{\"type\":\"number\",\"nullable\":true}" +
    (if recursive {
      ",\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}"
    } else {
      ""
    }) +
    "},\"rows\":[{\"bucket\":{\"literal\":\"a\"},\"n\":1" +
    (if recursive { ",\"payload\":{\"literal\":[1]}" } else { "" }) +
    "}]},\"as\":\"seed\"},{\"group\":{\"by\":[\"bucket\"],\"aggregates\":{\"total\":" +
    aggregate +
    "}}}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["group_1"],
    10000,
    1000,
  ).unwrap()
  select_generated_sequence_step(generated, 1).unwrap()
}

///|
test "direct Number group borrows only its existing scalar constructor input" {
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
  for
    (recursive, aggregate, borrowed) in [
      (false, "{\"fn\":\"sum\",\"field\":\"n\"}", true),
      (false, "{\"fn\":\"avg\",\"field\":\"n\"}", true),
      (true, "{\"fn\":\"sum\",\"field\":\"n\"}", false),
      (
        false, "{\"fn\":\"array_agg\",\"field\":\"n\",\"max_items\":5,\"order_by\":[{\"n\":\"asc\"}]}",
        false,
      ),
      (false, "{\"fn\":\"sum\",\"field\":\"n\",\"distinct\":true}", false),
    ] {
    let selected = number_group_capacity_fixture(recursive, aggregate)
    guard generated_sequence_step_at(selected, 0)
      is Some(@lower.RowStep(kernel)) else {
      fail("original group kernel missing")
    }
    assert_eq(bounded_number_group_borrows_input(kernel), borrowed)
    let original = generated_bounded_sequence_capacity(
      selected, limits, measure,
    ).unwrap()
    let enlarged = generated_bounded_sequence_capacity(selected, limits, large).unwrap()
    if borrowed {
      assert_eq(
        (original.retained_bytes, original.execution_bytes),
        (enlarged.retained_bytes, enlarged.execution_bytes),
      )
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
    } else {
      let full = generated_sequence_capacity(selected, limits, measure).unwrap()
      assert_eq(
        (original.retained_bytes, original.execution_bytes),
        (full.retained_bytes, full.execution_bytes),
      )
      assert_true(enlarged.execution_bytes > original.execution_bytes)
    }
  }
}
