///|
test "owned flat Ranking constructor preserves full holding and real bounded execution" {
  let source = ranking_name_source(["bucket", "id", "rank"])
  let owner = ranking_name_owner(source, ["bucket"], "id", "rank")
  let generated = task_test_generated(owner)
  let values : @execution.ValueLimits = {
    max_nodes: 2000,
    max_text_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  let limits = {
    ..compute_test_limits(),
    rows: {
      ..compute_test_limits().rows,
      input_values: values,
      output_values: values,
      operation_entries: 10000,
      retained_entries: 10000,
      metadata_entries: 10000,
    },
    max_work: 20000000,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_nodes: 20000,
    max_bytes: 120058033,
    max_depth: 100,
    max_work: 20000000,
  }
  let full = @execution.generated_sequence_capacity(
    generated, limits, measurement,
  ).unwrap()
  let bounded = @execution.generated_bounded_ranking_capacity(
    generated, limits, measurement, 10000,
  ).unwrap()
  assert_eq(bounded.retained_bytes, full.retained_bytes)
  assert_true(bounded.execution_bytes < full.execution_bytes)
  assert_true(bounded.retained_bytes + bounded.execution_bytes < 536870912L)
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
  let provider = @local_veca_provider.provider(
    records,
    100000L,
    full,
    bounded_constructor=true,
  )
  let legacy = @local_veca_provider.provider(records, 100000L, full)
  let selected = @local_connector.managed_provider_capacity_for_execution(
    provider, generated, limits, measurement,
  ).unwrap()
  assert_eq(selected.retained_bytes, full.retained_bytes)
  assert_eq(selected.execution_bytes, bounded.execution_bytes)
  assert_eq(
    @local_connector.managed_provider_capacity_for_execution(
      legacy, generated, limits, measurement,
    ).unwrap().execution_bytes,
    full.execution_bytes,
  )
  assert_true(
    @execution.generated_bounded_ranking_capacity(
      generated, limits, measurement, -1,
    )
    is None,
  )
  let recursive = ranking_name_source(["bucket", "id", "rank"], unused=Some(1))
  let recursive_owner = ranking_name_owner(recursive, ["bucket"], "id", "rank")
  assert_true(
    @execution.generated_bounded_ranking_capacity(
      task_test_generated(recursive_owner),
      limits,
      measurement,
      10000,
    )
    is None,
  )
  let populated = ranking_name_output(source, "id", "rank", false)
  let empty = ranking_name_output(source, "id", "rank", true)
  let inputs = [populated, empty].mapi((index, output) => {
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, index, source, output).unwrap(),
      1000,
      10000,
    ).unwrap()
  })
  let active = @local_connector.start_managed_provider_with_execution(
    provider, generated, inputs, 10, 10000, limits,
  ).unwrap()
  let mut result : @execution.CompletedOutput? = None
  for _ in 0..<1000 {
    match @local_connector.advance_managed_provider(active, 1).unwrap() {
      Complete(output, ..) => {
        result = Some(output)
        break
      }
      Continue(..) => ()
      _ => fail("original flat Ranking did not complete")
    }
  }
  let output = result.unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@execution.completed_output_available(output))
  for input in inputs {
    assert_true(@execution.producer_read_available(input))
  }
}
