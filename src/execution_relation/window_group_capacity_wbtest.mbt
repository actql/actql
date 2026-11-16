///|
test "dynamic bounded window group borrows original cells only with its same Fragment context" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"amount\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"id\":3,\"amount\":30},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"id\",\"size\":10}},{\"window_group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"},\"total\":{\"fn\":\"sum\",\"expr\":{\"add\":[{\"coalesce\":[{\"field\":\"amount\"},{\"literal\":0}]},{\"literal\":1}]},\"filter\":{\"not\":{\"is_null\":{\"field\":\"amount\"}}},\"distinct\":true}}}}]",
  )
  let sequence = prepared_sequence(owner)
  let values : ValueLimits = {
    max_nodes: 20000,
    max_text_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  let limits : SequenceExecutionLimits = {
    rows: {
      max_rows: 100,
      retained_entries: 10000,
      metadata_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 20000000,
    max_frames: 100,
  }
  let measurement : FixedInputGuardMeasureLimits = {
    max_work: 20000000,
    max_bytes: 10000,
    max_nodes: 20000,
    max_depth: 100,
  }
  let large = { ..measurement, max_bytes: 120000000, max_nodes: 50000, }
  for supported in [false, true] {
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      if supported {
        [sequence_fragment_context(sequence, 2, 10L)]
      } else {
        []
      },
      [
        @lower.node_id(
          @lower.node_at(@lower.bound_preparation(owner), 2).unwrap(),
        ),
      ],
      100000,
      10000,
    )
    if !supported {
      // The original constructor refuses a required Fragment context before
      // any runtime or narrowed constructor receipt can be issued.
      assert_true(generated is Err(_))
      continue
    }
    let generated = generated.unwrap()
    let selected = select_generated_sequence_step(generated, 2).unwrap()
    let bounded = generated_bounded_sequence_capacity(
      selected, limits, measurement,
    ).unwrap()
    let enlarged = generated_bounded_sequence_capacity(selected, limits, large).unwrap()
    let general = generated_sequence_capacity(selected, limits, large).unwrap()
    assert_eq(bounded.retained_bytes, enlarged.retained_bytes)
    let output_data = execution_capacity_inventory_bytes([
      { unit: ValueNodeSlots, count: values.max_nodes.to_int64(), copies: 1, },
      {
        unit: DecodedTextBytes,
        count: values.max_text_bytes.to_int64(),
        copies: 1,
      },
    ]).unwrap()
    assert_true(enlarged.retained_bytes >= output_data)
    // The actual constructor uses stepped original-cell measurement, while
    // its complete Fragment workspace and all output DATA remain charged.
    assert_eq(bounded.execution_bytes, enlarged.execution_bytes)
    assert_true(enlarged.execution_bytes < general.execution_bytes)
    assert_true(enlarged.execution_bytes > enlarged.retained_bytes)
  }
}
