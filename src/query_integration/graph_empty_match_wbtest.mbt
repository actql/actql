///|
test "empty keyed MATCH retains exact admission stop and cleanup obligations" {
  let nodes = keyed_node_source(rows="[]")
  let edges = keyed_edge_source(rows="[]")
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_graph(
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
    fail("constructor failed")
  }
  let owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"where\":\"false\",\"fields\":[\"display\"]}}]",
  )
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let preparation = task_test_completion(owner)
  let sequence = prepared_sequence(owner)
  let limits : @execution.ValueLimits = {
    max_work: 1000,
    max_nodes: 100,
    max_text_bytes: 1000,
    max_depth: 10,
  }
  // Empty selection has no sort slots, but retains one output column slot.
  // Only Finish consumes control work; it still needs an exact output owner.
  for viewed in [false, true] {
    let start = fn(control, workspace, work) {
      if viewed {
        @local_sga.start_match_nodes_view(
          control,
          preparation,
          sequence,
          0,
          @graphs.producer_read_view(input).unwrap(),
          0,
          limits,
          workspace,
          100,
          1000,
          [],
          control_work_limit=Some(work),
        )
      } else {
        @local_sga.start_match_nodes(
          control,
          preparation,
          sequence,
          0,
          input,
          0,
          limits,
          workspace,
          100,
          1000,
          [],
          control_work_limit=Some(work),
        )
      }
    }
    assert_true(
      start(@bounded.control(), 0, 1)
      is Err(@local_sga.MatchNodesWorkspaceLimit),
    )
    for quantum in [1, 7] {
      for allowed in [0, 1] {
        let active = start(@bounded.control(), 1, allowed).unwrap()
        match @local_sga.advance_match_nodes(active, quantum).unwrap() {
          @local_sga.MatchNodesComplete(output, work=1L, ..) => {
            assert_eq(allowed, 1)
            assert_eq(@execution.completed_row_count(output), 0)
            assert_true(@execution.completed_output_available(output))
          }
          @local_sga.MatchNodesFailed(
            @local_sga.MatchNodesWorkLimit,
            work=0L,
            ..
          ) => assert_eq(allowed, 0)
          _ => fail("empty MATCH must not bypass control admission")
        }
        assert_true(@local_sga.cleanup_match_nodes(active).unwrap())
        assert_false(@local_sga.cleanup_match_nodes(active).unwrap())
        assert_false(@local_sga.match_nodes_cleanup_pending(active))
        assert_eq(@local_sga.match_nodes_scratch_slots(active), 0)
        assert_true(@graphs.producer_read_available(input))
      }
    }
    let control = @bounded.control()
    let active = start(control, 1, 1).unwrap()
    assert_true(@bounded.request_cancel(control))
    assert_true(
      @local_sga.advance_match_nodes(active, 1)
      is Ok(@local_sga.MatchNodesStopped(_, work=0L, ..)),
    )
    assert_true(@local_sga.match_nodes_stopped(active))
    assert_true(@local_sga.cleanup_match_nodes(active).unwrap())
    assert_false(@local_sga.cleanup_match_nodes(active).unwrap())
    assert_false(@local_sga.match_nodes_cleanup_pending(active))
    assert_true(@local_sga.advance_match_nodes(active, 1) is Err(_))
    assert_true(@graphs.producer_read_available(input))
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
