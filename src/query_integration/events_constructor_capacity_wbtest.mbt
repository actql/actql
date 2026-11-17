///|
test "owned numeric Events constructor keeps full DATA and both record generations" {
  let source = carrier_events_source_owner()
  let owner = carrier_events_owner(source)
  let generated = task_test_generated(owner)
  let values : @execution.ValueLimits = {
    max_nodes: 28,
    max_text_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  let limits : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 2,
      input_values: values,
      output_values: values,
      operation_entries: 10000,
      retained_entries: 10000,
      metadata_entries: 10000,
    },
    max_frames: 100,
    max_work: 20000000,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_bytes: 120000845,
    max_nodes: 20000,
    max_depth: 100,
    max_work: 20000000,
  }
  let full = @execution.generated_sequence_capacity(
    generated, limits, measurement,
  ).unwrap()
  let bounded = @execution.generated_bounded_events_projection_capacity(
    generated, limits, measurement,
  ).unwrap()
  assert_eq(full.retained_bytes, 165127168L)
  assert_eq(bounded.retained_bytes, full.retained_bytes)
  assert_eq(full.execution_bytes - bounded.execution_bytes, 8L * 120000845L)
  // Input DATA and measurement-node ceilings remain real independent costs.
  let more_input = @execution.generated_bounded_events_projection_capacity(
    generated,
    {
      ..limits,
      rows: { ..limits.rows, input_values: { ..values, max_nodes: 29, }, },
    },
    measurement,
  ).unwrap()
  assert_eq(more_input.execution_bytes - bounded.execution_bytes, 256L)
  let more_measurement = @execution.generated_bounded_events_projection_capacity(
    generated,
    limits,
    { ..measurement, max_nodes: 20001, },
  ).unwrap()
  assert_eq(more_measurement.execution_bytes - bounded.execution_bytes, 256L)
  let records : @record_storage.Limits = {
    max_input_records: 100,
    max_records: 100,
    max_fields_per_record: 100,
    max_value_bytes: 10000,
    max_total_value_bytes: 100000,
    max_retained_value_bytes: 100000,
    max_value_nodes: 10000,
    max_value_depth: 100,
    max_contract_work: 10000,
    max_work: 100000,
    max_workspace_slots: 10000,
  }
  let provider = @local_tea_provider.provider(
    records,
    100000L,
    full,
    bounded_constructor=true,
  )
  let selected = @local_connector.managed_provider_capacity_for_execution(
    provider, generated, limits, measurement,
  ).unwrap()
  assert_eq(selected.retained_bytes, full.retained_bytes)
  assert_eq(selected.execution_bytes, bounded.execution_bytes + 17341184L)
  let legacy = @local_tea_provider.provider(records, 100000L, full)
  assert_eq(
    @local_connector.managed_provider_capacity_for_execution(
      legacy, generated, limits, measurement,
    ).unwrap().execution_bytes,
    full.execution_bytes + 200000L,
  )
  // The exact original scalar assessment's remaining Task/transport class is
  // retained unchanged here; this is a quantity proof, not Run acceptance.
  assert_true(selected.execution_bytes + 166002048L + 20013572L < 536870912L)
  for variant in ["dedupe", "window_fixed", "session"] {
    assert_true(
      @execution.generated_bounded_events_projection_capacity(
        task_test_generated(carrier_events_owner(source, variant~)),
        limits,
        measurement,
      )
      is None,
    )
  }
  let timestamp_source = carrier_events_source_owner_with("timestamp", "[]")
  assert_true(
    @execution.generated_bounded_events_projection_capacity(
      task_test_generated(carrier_events_owner(timestamp_source)),
      limits,
      measurement,
    )
    is None,
  )
  let source_output = carrier_events_source_output(source)
  let input = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source, source_output).unwrap(),
    100,
    1000,
  ).unwrap()
  let active = @local_connector.start_managed_provider_with_execution(
    provider,
    generated,
    [input],
    2,
    100000,
    limits,
  ).unwrap()
  let mut result : @execution.CompletedOutput? = None
  for _ in 0..<10000 {
    match @local_connector.advance_managed_provider(active, 1).unwrap() {
      Complete(output, ..) => {
        result = Some(output)
        break
      }
      Continue(..) => ()
      _ => fail("original stepped Events pipeline did not complete")
    }
  }
  let output = result.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@execution.completed_output_available(output))
  assert_true(@execution.producer_read_available(input))
}
