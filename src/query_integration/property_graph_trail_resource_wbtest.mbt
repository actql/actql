///|
test "current path variants retain independent exact work workspace and every private stop boundary" {
  let nodes = keyed_node_source()
  // Independent parallel edge keys make the scan ceiling exceed
  // output value-admission work without adding a second work-budget API.
  let edge_count = 100
  let edge_rows = []
  for key in 0..<edge_count {
    edge_rows.push(
      "{\"key\":" + key.to_string() + ",\"tenant\":\"a\",\"src\":1,\"dst\":1}",
    )
  }
  let edges = keyed_edge_source(rows="[" + edge_rows.join(",") + "]")
  // Five definitions reuse the same 100-row producer without inventing a
  // new acquisition or execution owner. Element keys remain definition-scoped.
  let definitions = []
  for index in 0..<5 {
    definitions.push(
      "{\"name\":\"E" +
      index.to_string() +
      "\",\"from\":\"edges\",\"key\":[\"key\"],\"source\":{\"definition\":\"N\",\"key\":[\"tenant\",\"src\"]},\"target\":{\"definition\":\"N\",\"key\":[\"tenant\",\"dst\"]},\"labels\":[{\"name\":\"R\",\"properties\":{\"mode\":\"no_properties\"}}]}",
    )
  }
  let graph_owner = keyed_bridge_owner(
    nodes,
    edges,
    body=Some(
      "[{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"nodes\",\"key\":[\"tenant\",\"id\"],\"labels\":[{\"name\":\"Node\",\"properties\":{\"mode\":\"columns\",\"columns\":[{\"from\":\"name\",\"to\":\"display\"}]}}]}],\"edges\":[" +
      definitions.join(",") +
      "]},\"as\":\"g\"}]",
    ),
  )
  let inputs = keyed_bridge_inputs(graph_owner, nodes, edges)
  for _ in 0..<4 {
    inputs.push(inputs[1])
  }
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    inputs,
    {
      ..carrier_graph_storage_limits(),
      max_input_rows: 2000,
      max_edges: 5 * edge_count,
      max_total_value_bytes: 1000000,
      max_retained_value_bytes: 1000000,
      max_work: 1000000,
      max_workspace_slots: 100000,
    },
    8388608L,
    100000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction, max_fixture_steps=100000)
    is @local_bridge.Complete(graph, ..) else {
    fail("constructor failed")
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
  let identity = "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[\"a\",1],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}"
  let expected = "{\"edge_ids\":[],\"end_id\":" +
    property_graph_expected_json_wire(identity) +
    ",\"hop_count\":0,\"node_ids\":[" +
    property_graph_expected_json_wire(identity) +
    "],\"start_id\":" +
    property_graph_expected_json_wire(identity) +
    "}"
  // One real, nonempty zero-hop path: initialize/resolve/collect (3),
  // scalar fields (3), one node-array append (1), two array finalizations (2),
  // private row commit (1), finish (1), then each physical edge occurrence
  // (twice for Both). A self-loop is a candidate once, even for Both.
  // WALK checks that candidate; ACYCLIC rejects its repeated node in one
  // step; TRAIL's empty edge membership costs no extra step.
  // The explicitly empty label filter excludes all remaining candidates.
  // No measured work supplies this oracle.
  // Start index (1), frontier path + its node (2), node-array slots (2),
  // empty edge-array slot (1) overlap until the private row commits.
  let workspace = 1 + 2 + 2 + 1
  for mode in ["walk", "trail", "acyclic"] {
    for direction in ["out", "in", "both"] {
      let work = 3 +
        3 +
        1 +
        2 +
        1 +
        1 +
        5 *
        edge_count *
        (
          (if direction == "both" { 2 } else { 1 }) +
          (if mode == "trail" { 0 } else { 1 })
        )
      let owner = keyed_graph_receiver(
        graph_owner,
        body="[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
          identity +
          "]},\"direction\":\"" +
          direction +
          "\",\"min_hops\":0,\"max_hops\":1,\"edge_types\":[],\"path_mode\":\"" +
          mode +
          "\",\"emit\":\"paths\"}}]",
      )
      let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
      let preparation = task_test_completion(owner)
      for viewed in [false, true] {
        let start = fn(control, slots, allowed_work) {
          let limits : @execution.ValueLimits = {
            max_work: allowed_work,
            max_nodes: 1000,
            max_text_bytes: 10000,
            max_depth: 50,
          }
          if viewed {
            @local_sga.start_traverse_view(
              control,
              preparation,
              prepared_sequence(owner),
              0,
              @graphs.producer_read_view(input).unwrap(),
              1,
              limits,
              slots,
              10000,
              10000,
              [],
            ).unwrap()
          } else {
            @local_sga.start_traverse(
              control,
              preparation,
              prepared_sequence(owner),
              0,
              input,
              1,
              limits,
              slots,
              10000,
              10000,
              [],
            ).unwrap()
          }
        }
        for quantum in [1, 7, 1024] {
          for
            (slots, allowed, expected_failure) in [
              (workspace, work, ""),
              (workspace - 1, work, "workspace"),
              (workspace, work - 1, "work"),
            ] {
            let active = start(@bounded.control(), slots, allowed)
            let mut terminal = false
            for _ in 0..<(work + 1) {
              match @local_sga.advance_traverse(active, quantum).unwrap() {
                @local_sga.TraverseContinue(..) => ()
                @local_sga.TraverseComplete(output, work=spent, ..) => {
                  assert_eq(expected_failure, "")
                  assert_eq(spent, work.to_int64())
                  assert_eq(@execution.completed_row_count(output), 1)
                  assert_eq(
                    @execution.completed_output_row_wire(
                      output, 0, 10000, 10000, 50,
                    ).unwrap(),
                    expected,
                  )
                  terminal = true
                  break
                }
                @local_sga.TraverseFailed(
                  @local_sga.TraversePathIssue(
                    @local_sga.TraversePathsWorkspaceLimit
                  ),
                  ..
                ) => {
                  assert_eq(expected_failure, "workspace")
                  terminal = true
                  break
                }
                @local_sga.TraverseFailed(
                  @local_sga.TraversePathIssue(
                    @local_sga.TraversePathsWorkLimit
                  ),
                  work=spent,
                  ..
                ) => {
                  assert_eq(expected_failure, "work")
                  assert_eq(spent, allowed.to_int64())
                  terminal = true
                  break
                }
                @local_sga.TraverseFailed(_, ..) =>
                  fail("unexpected current path failure")
                _ => fail("unexpected current path terminal")
              }
            }
            assert_true(terminal)
            assert_true(@local_sga.traverse_cleanup_pending(active))
            assert_true(@local_sga.cleanup_traverse(active).unwrap())
            assert_false(@local_sga.cleanup_traverse(active).unwrap())
            assert_false(@local_sga.traverse_cleanup_pending(active))
            assert_eq(@local_sga.traverse_private_entry_count(active), 0)
            assert_true(@graphs.producer_read_available(input))
          }
        }
        for prefix in 0..<work {
          let control = @bounded.control()
          let active = start(control, workspace, work)
          for index in 0..<prefix {
            assert_true(
              @local_sga.advance_traverse(active, 1)
              is Ok(@local_sga.TraverseContinue(work~, ..)) &&
              work == (index + 1).to_int64(),
            )
          }
          assert_true(@bounded.request_cancel(control))
          assert_true(
            @local_sga.advance_traverse(active, 1)
            is Ok(@local_sga.TraverseStopped(_, work=spent, ..)) &&
            spent == prefix.to_int64(),
          )
          assert_true(@local_sga.cleanup_traverse(active).unwrap())
          assert_false(@local_sga.cleanup_traverse(active).unwrap())
          assert_false(@local_sga.traverse_cleanup_pending(active))
          assert_eq(@local_sga.traverse_private_entry_count(active), 0)
          assert_true(@graphs.producer_read_available(input))
        }
      }
    }
  }
  // A nonempty unmatched label visits exactly one additional charged label
  // comparison per eligible edge. TRAIL admits every first edge, so all five
  // definition-scoped copies of the 100 source edges each cost one scan and
  // one label comparison after the eleven zero-hop control/value steps.
  let labeled_work = 3 + 3 + 1 + 2 + 1 + 1 + 2 * 5 * edge_count
  let labeled_owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
      identity +
      "]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":1,\"edge_types\":[\"Missing\"],\"path_mode\":\"trail\",\"emit\":\"paths\"}}]",
  )
  let labeled_input = @graphs.prepare_producer_read(
    labeled_owner, 0, graph_owner, graph,
  ).unwrap()
  let labeled_preparation = task_test_completion(labeled_owner)
  for viewed in [false, true] {
    let start = fn(control, slots, allowed_work) {
      let limits : @execution.ValueLimits = {
        max_work: allowed_work,
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 50,
      }
      if viewed {
        @local_sga.start_traverse_view(
          control,
          labeled_preparation,
          prepared_sequence(labeled_owner),
          0,
          @graphs.producer_read_view(labeled_input).unwrap(),
          1,
          limits,
          slots,
          10000,
          10000,
          [],
        ).unwrap()
      } else {
        @local_sga.start_traverse(
          control,
          labeled_preparation,
          prepared_sequence(labeled_owner),
          0,
          labeled_input,
          1,
          limits,
          slots,
          10000,
          10000,
          [],
        ).unwrap()
      }
    }
    for quantum in [1, 127] {
      let spent = Ref(0L)
      let exact = start(@bounded.control(), workspace, labeled_work)
      let output = finish_traverse(exact, quantum~, spent_work=Some(spent)).unwrap()
      assert_eq(spent.val, labeled_work.to_int64())
      assert_eq(@execution.completed_row_count(output), 1)
      assert_eq(
        @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
        expected,
      )
      assert_true(@local_sga.cleanup_traverse(exact).unwrap())
      let short = start(@bounded.control(), workspace, labeled_work - 1)
      let short_spent = Ref(0L)
      assert_true(
        finish_traverse(short, quantum~, spent_work=Some(short_spent))
        is Err(@local_sga.TraversePathIssue(@local_sga.TraversePathsWorkLimit)),
      )
      assert_eq(short_spent.val, (labeled_work - 1).to_int64())
      assert_true(@local_sga.cleanup_traverse(short).unwrap())
      assert_eq(@local_sga.traverse_private_entry_count(short), 0)
      let no_workspace = start(@bounded.control(), workspace - 1, labeled_work)
      assert_true(
        finish_traverse(no_workspace, quantum~)
        is Err(
          @local_sga.TraversePathIssue(@local_sga.TraversePathsWorkspaceLimit)
        ),
      )
      assert_true(@local_sga.cleanup_traverse(no_workspace).unwrap())
      assert_eq(@local_sga.traverse_private_entry_count(no_workspace), 0)
    }
    let control = @bounded.control()
    let stopped = start(control, workspace, labeled_work)
    for index in 0..<20 {
      assert_true(
        @local_sga.advance_traverse(stopped, 1)
        is Ok(@local_sga.TraverseContinue(work~, ..)) &&
        work == (index + 1).to_int64(),
      )
    }
    assert_true(@bounded.request_cancel(control))
    guard @local_sga.advance_traverse(stopped, 1)
      is Ok(@local_sga.TraverseStopped(_, work=spent, ..)) else {
      fail("label scan did not stop")
    }
    assert_eq(spent, 20L)
    assert_true(@local_sga.cleanup_traverse(stopped).unwrap())
    assert_eq(@local_sga.traverse_private_entry_count(stopped), 0)
    assert_true(@graphs.producer_read_available(labeled_input))
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
