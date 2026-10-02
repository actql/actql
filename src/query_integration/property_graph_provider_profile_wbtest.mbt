///|
test "retired tuple constructor cannot issue an executable generated sequence" {
  let source = carrier_graph_source_owner()
  let produced = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source)),
    @pipeline.Step(0),
  ).unwrap()
  for projection in ["", ",{\"node_rows\":true}", ",{\"edge_rows\":true}"] {
    let body = "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\",\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\",\"source\":\"src\",\"target\":\"dst\",\"fields\":[\"weight\"]}},\"as\":\"graph\"}" +
      projection +
      "]"
    guard @pipeline.check_with_evidence(
        input_cursor(body),
        [("rows", @pipeline.ProducedInput(produced))],
        None,
        Some(input_cursor("\"rows\"")),
        {
          max_steps: 10,
          max_work: 10000,
          max_text_bytes: 10000,
          max_nodes: 1000,
          max_tokens: 1000,
          max_depth: 100,
        },
      )
      is Err(_) else {
      fail("historical constructor was accepted")
    }
  }
}

///|
test "historical MATCH and traversal are rejected before a generated sequence exists" {
  let empty = @carrier_contract.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  // Historical schema knowledge is a negative fixture, never a producer owner.
  assert_true(
    @carrier_contract.graph(
      @value_contract.primitive(NumberType, nullable=false),
      empty,
      empty,
      labels=None,
      max_labels=0,
      max_label_bytes=0,
    )
    is Err(UnsupportedGraphProfile),
  )
  let historical = @carrier_contract.unknown_carrier(GraphKind)
  for
    body in [
      "[{\"from\":\"g\",\"match_nodes\":{\"ids\":[1],\"fields\":[\"id\"]},\"as\":\"out\"}]",
      "[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[1]},\"hops\":[{\"direction\":\"out\"}],\"emit\":\"paths\"},\"as\":\"out\"}]",
    ] {
    assert_true(
      @pipeline.check_carriers(
        input_cursor(body),
        [("g", historical)],
        None,
        None,
        {
          max_steps: 10,
          max_work: 10000,
          max_text_bytes: 10000,
          max_nodes: 1000,
          max_tokens: 1000,
          max_depth: 100,
        },
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
