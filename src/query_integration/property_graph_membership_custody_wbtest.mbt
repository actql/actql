///|
test "current MATCH rejects an absent same-domain typed identity without publishing partial rows" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    8192L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("current constructor must complete")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(contract)) else {
    fail("current Graph contract")
  }
  let domain = @carrier_contract.property_graph_domain(
    @carrier_contract.graph_property_definition(contract),
  )
  let identity = fn(key : Int) {
    "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[\"a\"," +
    key.to_string() +
    "],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}"
  }
  let receiver = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"ids\":[" +
      identity(1) +
      "," +
      identity(3) +
      "],\"bindings\":{\"identity\":\"element\"},\"fields\":[\"element\"]}}]",
  )
  let input = @graphs.prepare_producer_read(receiver, 0, graph_owner, graph).unwrap()
  let preparation = task_test_completion(receiver)
  for viewed in [false, true] {
    let limits : @execution.ValueLimits = {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 50,
    }
    let active = if viewed {
      @local_sga.start_match_nodes_view(
        @bounded.control(),
        preparation,
        prepared_sequence(receiver),
        0,
        @graphs.producer_read_view(input).unwrap(),
        2,
        limits,
        1000,
        10000,
        10000,
        [],
      ).unwrap()
    } else {
      @local_sga.start_match_nodes(
        @bounded.control(),
        preparation,
        prepared_sequence(receiver),
        0,
        input,
        2,
        limits,
        1000,
        10000,
        10000,
        [],
      ).unwrap()
    }
    assert_true(
      finish_match_nodes(active) is Err(@local_sga.MissingMatchNodeIdentity(1)),
    )
    assert_true(@local_sga.match_nodes_cleanup_pending(active))
    assert_true(@local_sga.cleanup_match_nodes(active).unwrap())
    assert_false(@local_sga.cleanup_match_nodes(active).unwrap())
    assert_false(@local_sga.match_nodes_cleanup_pending(active))
    assert_true(@graphs.producer_read_available(input))
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "current TRAIL rejects oversized identity arrays before allocation and admits the exact typed output ceiling" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    8192L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("current constructor must complete")
  }
  let (owner, _) = keyed_path_owner(graph_owner, "trail")
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let preparation = task_test_completion(owner)
  for viewed in [false, true] {
    // Independently count the authored typed row: root 1, hop_count 1,
    // start/end identities 2*11, node_ids 1+3*11, edge_ids 1+2*8 = 75.
    // Two distinct TRAIL rows therefore require 150 admitted output nodes.
    // The former scalar-key row ceiling was representation-specific.
    for ceiling in [16, 149, 150] {
      let limits : @execution.ValueLimits = {
        max_work: 100000,
        max_nodes: ceiling,
        max_text_bytes: 10000,
        max_depth: 50,
      }
      let active = if viewed {
        @local_sga.start_traverse_view(
          @bounded.control(),
          preparation,
          prepared_sequence(owner),
          0,
          @graphs.producer_read_view(input).unwrap(),
          10,
          limits,
          20000,
          10000,
          10000,
          [],
        ).unwrap()
      } else {
        @local_sga.start_traverse(
          @bounded.control(),
          preparation,
          prepared_sequence(owner),
          0,
          input,
          10,
          limits,
          20000,
          10000,
          10000,
          [],
        ).unwrap()
      }
      let terminal = finish_traverse(active)
      if ceiling == 150 {
        guard terminal is Ok(output) else {
          fail("exact typed output ceiling must complete")
        }
        assert_eq(@execution.completed_row_count(output), 2)
      } else {
        match terminal {
          Err(issue) =>
            assert_eq(
              issue,
              if ceiling == 16 {
                @local_sga.TraversePathIssue(
                  @local_sga.TraversePathsOutputLimit,
                )
              } else {
                @local_sga.TraversePathIssue(
                  @local_sga.TraversePathsOutput(@execution.CaptureLimit),
                )
              },
            )
          Ok(_) => fail("unexpected success at ceiling " + ceiling.to_string())
        }
        assert_true(@local_sga.traverse_cleanup_pending(active))
        if ceiling == 16 {
          assert_eq(@local_sga.traverse_value_item_attempts(active), 0)
        }
      }
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.traverse_cleanup_pending(active))
      assert_eq(@local_sga.traverse_private_entry_count(active), 0)
      assert_true(@graphs.producer_read_available(input))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
