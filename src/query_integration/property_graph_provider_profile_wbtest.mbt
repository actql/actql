///|
test "current Graph provider refuses retired constructor projection MATCH and traversal at both selection boundaries" {
  let source = carrier_graph_source_owner()
  let graph = carrier_graph_material_owner(source)
  let projection = task_test_generated(carrier_graph_owner(source))
  let matched = task_test_generated(carrier_selected_match_owner(graph, true))
  let traversed = task_test_generated(
    carrier_graph_traverse_owner(source, 1, 2, emission="paths"),
  )
  let construction = task_test_generated(graph)
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.execution_capacity(4096L, 65536L).unwrap(),
  )
  // These historical fixtures deliberately bypass normal Program rejection.
  // A typed low-level selection must not reopen executable legacy fallback.
  for
    sequence in [
      construction,
      @execution.select_generated_sequence_step(construction, 0).unwrap(),
      projection,
      @execution.select_generated_sequence_step(projection, 1).unwrap(),
      @execution.select_generated_sequence_step(matched, 0).unwrap(),
      traversed,
      @execution.select_generated_sequence_step(traversed, 1).unwrap(),
    ] {
    assert_false(@local_connector.managed_provider_accepts(provider, sequence))
    assert_true(
      @local_connector.managed_provider_capacity(provider, sequence) is None,
    )
    assert_true(
      @local_connector.start_managed_provider_with_inputs(
        provider,
        sequence,
        [],
        10,
        1000,
      )
      is Err(_),
    )
  }
}

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
