///|
test "current Graph provider keeps keyed constructor and explicit TRAIL on the existing owner" {
  let graph = keyed_bridge_owner(keyed_node_source(), keyed_edge_source())
  let (trail, _) = keyed_path_owner(graph, "trail")
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.execution_capacity(4096L, 65536L).unwrap(),
  )
  for
    sequence in [
      task_test_generated(graph),
      @execution.select_generated_sequence_step(task_test_generated(graph), 0).unwrap(),
      @execution.select_generated_sequence_step(task_test_generated(trail), 0).unwrap(),
    ] {
    assert_true(@local_connector.managed_provider_accepts(provider, sequence))
    assert_true(
      @local_connector.managed_provider_capacity(provider, sequence) is Some(_),
    )
  }
}
