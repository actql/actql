///|
test "ordinary keyed count chain reserves only one cleaned child scratch envelope" {
  let (run, issuer) = captured_graph_fixture(
    count=true,
    count_filter_chain=true,
    keyed_count_filter_chain=true,
  )
  let sequence = dispatch_test_generated(run)[0]
  let limits = dispatch_test_limits()
  let registry = search_registry()
  let installed = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [sequence],
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    1,
  ).unwrap()
  let provider = @local_connector.local_module_managed_provider(
    installed, sequence,
  ).unwrap()
  let capacity = @local_connector.managed_provider_capacity(provider, sequence).unwrap()
  let base = @execution.generated_sequence_capacity(
    sequence,
    limits.local_execution,
    limits.guards,
  ).unwrap()
  let mut retained = 0L
  let mut scratch = 0L
  let count = @execution.generated_sequence_step_count(sequence)
  assert_eq(count, 3)
  for index in 0..<count {
    let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
    let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
    let child = @execution.generated_sequence_capacity(
      selected,
      limits.local_execution,
      limits.guards,
    ).unwrap()
    retained += child.retained_bytes
    scratch = Int64::max(scratch, child.execution_bytes)
  }
  assert_true(retained + scratch > base.execution_bytes)
  assert_eq(capacity.retained_bytes, base.retained_bytes)
  assert_eq(
    capacity.execution_bytes,
    retained + scratch + count.to_int64() * 256L,
  )
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
}
