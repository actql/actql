///|
fn check_retained_sequence_offer(registered : Bool) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(local_values_sequence_chain=true)
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let generated = dispatch_test_generated(run)
  let capacity = @execution.generated_sequence_capacity(
    generated[1],
    limits.local_execution,
    limits.guards,
  ).unwrap()
  let provider = @local_tea_provider.sequence_match_provider(
    carrier_events_storage_limits(),
    capacity,
  )
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    generated,
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    managed_providers=if registered { [provider] } else { [] },
  ).unwrap()
  let wire = {
    ..retained_attempt_wire_limits(),
    max_bytes: 10000,
    max_columns: 10,
  }
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire,
      row: {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 10,
        max_text_bytes: 1000,
      },
      max_batch_bytes: 1024,
    },
    None,
  ).unwrap()
  @local_driver.configure_local_retained_output(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.output_values,
      wire,
      max_batch_bytes: 1024,
    },
    None,
  ).unwrap()
  let implementation = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    generated,
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    generated.length(),
    managed_providers=if registered { [provider] } else { [] },
  ).unwrap()
  assert_false(
    @local_connector.local_module_bounded_temporal_relation_obligation(
      implementation,
      1,
      1,
      @local_connector.SequenceMatch,
    ),
  )
  assert_false(
    @local_connector.local_module_bounded_temporal_relation_obligation(
      implementation,
      1,
      0,
      @local_connector.TimeSeries,
    ),
  )
  assert_eq(
    @local_connector.local_module_bounded_temporal_relation_obligation(
      implementation,
      1,
      0,
      @local_connector.SequenceMatch,
    ),
    registered,
  )
  assert_eq(
    @local_driver.local_dispatch_rejection(installed, 2),
    if registered {
      None
    } else {
      Some("unsupported_execution_obligation")
    },
  )
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "retained sequence rejects a missing bounded matcher" {
  check_retained_sequence_offer(false)
}

///|
test "retained sequence admits its registered bounded matcher" {
  check_retained_sequence_offer(true)
}
