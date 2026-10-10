///|
test "Reach and Shortest predicate admission yields inside Text with exact work workspace and cancellation" {
  let text = String::make(128, 'x') + "e\u{0301}\r\n"
  let out = @encode.writer(1000, 10, 10)
  @encode.string_value(out, text)
  let nodes = keyed_node_source(
    rows="[{\"id\":1,\"tenant\":\"a\",\"name\":" + @encode.finish(out) + "}]",
  )
  let edges = keyed_edge_source(rows="[]")
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    65536L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("Graph construction failed")
  }
  // Each selector pays initialize + resolve + binding + Text recheck
  // (node, three 64-unit fragments, terminal) + four IS NULL transitions.
  // Empty selection then pays collect + finish, with no retained row charge.
  let selector_work = 1 + 1 + 1 + (1 + 3 + 1) + 4
  for shortest in [false, true] {
    let body = if shortest {
      (
        #|[{"from":"g","shortest_path":{"source":{"where":"display IS NULL"},"target":{"where":"display IS NULL"},"selection":"each_pair","direction":"out","max_hops":1}}]
      )
    } else {
      (
        #|[{"from":"g","reach":{"start":{"where":"display IS NULL"},"direction":"out","max_depth":1}}]
      )
    }
    let owner = keyed_graph_receiver(graph_owner, body~)
    let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
    let total_work = selector_work * (if shortest { 2 } else { 1 }) + 2
    // Selection bitmaps + binding root + cursor + frame + one growth slot.
    let workspace = (if shortest { 2 } else { 1 }) + 4
    let preparation = task_test_completion(owner)
    let start = fn(control, work, slots) {
      @local_sga.start_traverse_view(
        control,
        preparation,
        prepared_sequence(owner),
        0,
        @graphs.producer_read_view(input).unwrap(),
        0,
        {
          max_work: work,
          max_nodes: 10000,
          max_text_bytes: 10000,
          max_depth: 50,
        },
        slots,
        10000,
        10000,
        [],
      ).unwrap()
    }
    for quantum in [1, 7, 64] {
      for
        (work, slots, failure) in [
          (total_work, workspace, None),
          (total_work - 1, workspace, Some(@local_sga.TraversePathsWorkLimit)),
          (
            total_work,
            workspace - 1,
            Some(@local_sga.TraversePathsWorkspaceLimit),
          ),
        ] {
        let active = start(@bounded.control(), work, slots)
        let mut previous = 0L
        for _ in 0..<100 {
          match @local_sga.advance_traverse(active, quantum).unwrap() {
            @local_sga.TraverseContinue(work=w, ..) => {
              assert_true(w >= previous && w - previous <= quantum.to_int64())
              previous = w
            }
            @local_sga.TraverseComplete(output, work=w, ..) => {
              assert_eq(failure, None)
              assert_eq(w, total_work.to_int64())
              assert_eq(@execution.completed_row_count(output), 0)
              assert_eq(
                @local_sga.traverse_private_workspace_usage(active).1,
                workspace,
              )
              break
            }
            @local_sga.TraverseFailed(@local_sga.TraversePathIssue(issue), ..) => {
              assert_eq(Some(issue), failure)
              break
            }
            _ => fail("unexpected selector terminal")
          }
        } nobreak {
          fail("finite selector fixture limit")
        }
        assert_true(@local_sga.cleanup_traverse(active).unwrap())
        assert_false(@local_sga.cleanup_traverse(active).unwrap())
        assert_eq(@local_sga.traverse_private_entry_count(active), 0)
        assert_eq(@local_sga.traverse_private_workspace_usage(active).0, 0)
        assert_true(@graphs.producer_read_available(input))
        assert_true(
          @graph_storage.node_property(
            @graphs.producer_read_storage(input).unwrap(),
            0,
            0,
          ).unwrap().value
          is @admitted.Text(original) &&
          original == text,
        )
      }
    }
    let control = @bounded.control()
    let active = start(control, total_work, workspace)
    // At work 6, two Text fragments have been checked, but neither the
    // complete binding nor its expression evaluator has been published.
    for index in 1..<=6 {
      guard @local_sga.advance_traverse(active, 1).unwrap()
        is @local_sga.TraverseContinue(work~, ..) else {
        fail("selector must yield before predicate execution")
      }
      assert_eq(work, index.to_int64())
    }
    assert_eq(@local_sga.traverse_predicate_starts(active), 0)
    assert_true(@local_sga.traverse_private_workspace_usage(active).0 > 0)
    assert_true(@graphs.producer_read_available(input))
    assert_true(
      @graph_storage.node_property(
        @graphs.producer_read_storage(input).unwrap(),
        0,
        0,
      ).unwrap().value
      is @admitted.Text(original) &&
      original == text,
    )
    assert_true(@bounded.request_cancel(control))
    assert_true(
      @local_sga.advance_traverse(active, 1).unwrap()
      is @local_sga.TraverseStopped(@bounded.Cancelled, work=6L, ..),
    )
    assert_true(@local_sga.traverse_stopped(active))
    assert_true(@local_sga.cleanup_traverse(active).unwrap())
    assert_false(@local_sga.cleanup_traverse(active).unwrap())
    assert_eq(@local_sga.traverse_private_entry_count(active), 0)
    assert_eq(@local_sga.traverse_private_workspace_usage(active).0, 0)
    assert_true(@graphs.producer_read_available(input))
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
