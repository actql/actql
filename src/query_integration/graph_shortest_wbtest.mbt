///|
test "Shortest shares bounded simple-path execution with typed parallel edges and zero-hop selection" {
  let nodes = keyed_node_source(
    rows="[{\"id\":3,\"tenant\":\"a\",\"name\":\"three\"},{\"id\":2,\"tenant\":\"a\",\"name\":\"two\"},{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"}]",
  )
  let edges = keyed_edge_source(
    rows="[{\"key\":11,\"tenant\":\"a\",\"src\":1,\"dst\":2},{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":2},{\"key\":12,\"tenant\":\"a\",\"src\":2,\"dst\":3},{\"key\":13,\"tenant\":\"a\",\"src\":1,\"dst\":3},{\"key\":14,\"tenant\":\"a\",\"src\":1,\"dst\":1}]",
  )
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    { ..carrier_graph_storage_limits(), max_work: 100000, },
    65536L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("Graph construction")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(carrier)) else {
    fail("typed Graph")
  }
  let domain = @carrier_contract.graph_domain(
    @carrier_contract.graph_definition(carrier),
  )
  for
    (target, expected_nodes, expected_edges, expected_cost) in [
      (1, [1], [], 0),
      (2, [1, 2], [10], 1),
      (3, [1, 3], [13], 1),
    ] {
    let owner = keyed_graph_receiver(
      graph_owner,
      body="[{\"from\":\"g\",\"shortest_path\":{\"source\":" +
        traversal_fixture_node(domain, 1) +
        ",\"target\":" +
        traversal_fixture_node(domain, target) +
        ",\"direction\":\"out\",\"max_hops\":2}}]",
    )
    let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
    let mut previous_work = None
    for quantum in [1, 7, 64] {
      let active = @local_sga.start_traverse_view(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        @graphs.producer_read_view(input).unwrap(),
        1,
        {
          max_work: 100000,
          max_nodes: 10000,
          max_text_bytes: 10000,
          max_depth: 50,
        },
        20000,
        10000,
        10000,
        [],
      ).unwrap()
      let mut work = 0L
      let mut completed = None
      for _ in 0..<100000 {
        match @local_sga.advance_traverse(active, quantum).unwrap() {
          @local_sga.TraverseContinue(work=w, ..) => {
            assert_true(w >= work && w - work <= quantum.to_int64())
            work = w
          }
          @local_sga.TraverseComplete(output, work=w, ..) => {
            work = w
            completed = Some(output)
            break
          }
          @local_sga.TraverseFailed(issue, ..) => fail(@debug.to_string(issue))
          _ => fail("unexpected cancellation")
        }
      } nobreak {
        fail("finite shortest fixture limit")
      }
      if previous_work is Some(expected) {
        assert_eq(work, expected)
      }
      previous_work = Some(work)
      let output = completed.unwrap()
      assert_eq(@execution.completed_row_count(output), 1)
      let expected_node_wire = expected_nodes
        .map(key => {
          graph_expected_json_wire(traversal_fixture_node(domain, key))
        })
        .join(",")
      let expected_edge_wire = expected_edges
        .map(key => {
          graph_expected_json_wire(
            "{\"definition\":\"E\",\"domain\":\"" +
            domain +
            "\",\"key\":[" +
            key.to_string() +
            "],\"key_types\":[{\"kind\":\"number\"}]}",
          )
        })
        .join(",")
      assert_eq(
        @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
        "{\"edge_ids\":[" +
        expected_edge_wire +
        "],\"hop_count\":" +
        expected_edges.length().to_string() +
        ",\"node_ids\":[" +
        expected_node_wire +
        "],\"source_id\":" +
        graph_expected_json_wire(traversal_fixture_node(domain, 1)) +
        ",\"target_id\":" +
        graph_expected_json_wire(traversal_fixture_node(domain, target)) +
        ",\"total_cost\":" +
        expected_cost.to_string() +
        "}",
      )
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      assert_eq(@local_sga.traverse_private_entry_count(active), 0)
      assert_true(@execution.completed_output_available(output))
      assert_true(@graphs.producer_read_available(input))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
}

///|
test "Shortest zero-hop execution has independently decomposed retained work workspace and mid-selection cancellation" {
  let nodes = keyed_node_source(
    rows="[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"}]",
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
    fail("Graph construction")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(carrier)) else {
    fail("Graph contract")
  }
  let domain = @carrier_contract.graph_domain(
    @carrier_contract.graph_definition(carrier),
  )
  let identity = traversal_fixture_node(domain, 1)
  let owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"shortest_path\":{\"source\":" +
      identity +
      ",\"target\":" +
      identity +
      ",\"direction\":\"out\",\"max_hops\":1}}]",
  )
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  // Independently derive the retained value budget, not from a successful
  // execution: one row, two arrays, two numbers and three occurrences of the
  // declared node identity (11 nodes each) = 38 nodes. Identity field names
  // and fixed Text contribute 50 bytes plus the authored domain per occurrence;
  // the six output names contribute 53 bytes. Work is nodes + Text bytes.
  let output_work = 38 + 3 * (50 + domain.length()) + 53
  // Workspace before output: two selector entries + winner(path,node,cost,
  // candidate)=4 + two arrays and their single node entry=3. The existing
  // output cursor adds a seven-slot row and at most three measurement frames.
  let output_workspace = 9 + 7 + 3
  for quantum in [1, 7, 64] {
    for
      (max_work, workspace, expected_issue) in [
        (output_work, output_workspace, None),
        (
          output_work - 1,
          output_workspace,
          Some(@local_sga.TraversePathsOutput(@execution.CaptureLimit)),
        ),
        (
          output_work,
          output_workspace - 1,
          Some(@local_sga.TraversePathsWorkspaceLimit),
        ),
      ] {
      let active = @local_sga.start_traverse_view(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        @graphs.producer_read_view(input).unwrap(),
        1,
        { max_work, max_nodes: 10000, max_text_bytes: 10000, max_depth: 50, },
        workspace,
        10000,
        10000,
        [],
      ).unwrap()
      for _ in 0..<1000 {
        match @local_sga.advance_traverse(active, quantum).unwrap() {
          @local_sga.TraverseContinue(..) => ()
          @local_sga.TraverseComplete(output, work~, ..) => {
            assert_true(expected_issue is None)
            assert_true(work <= output_work.to_int64())
            assert_eq(@execution.completed_row_count(output), 1)
            assert_eq(
              @local_sga.traverse_private_workspace_usage(active).1,
              output_workspace,
            )
            break
          }
          @local_sga.TraverseFailed(@local_sga.TraversePathIssue(issue), ..) => {
            assert_eq(Some(issue), expected_issue)
            break
          }
          _ => fail("unexpected shortest terminal")
        }
      } nobreak {
        fail("finite zero-hop fixture limit")
      }
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      assert_eq(@local_sga.traverse_private_entry_count(active), 0)
      assert_eq(@local_sga.traverse_private_workspace_usage(active).0, 0)
      assert_true(@graphs.producer_read_available(input))
    }
  }
  let control = @bounded.control()
  let active = @local_sga.start_traverse_view(
    control,
    task_test_completion(owner),
    prepared_sequence(owner),
    0,
    @graphs.producer_read_view(input).unwrap(),
    1,
    {
      max_work: output_work,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 50,
    },
    output_workspace,
    10000,
    10000,
    [],
  ).unwrap()
  for _ in 0..<1000 {
    assert_true(
      @local_sga.advance_traverse(active, 1).unwrap()
      is @local_sga.TraverseContinue(..),
    )
    if @local_sga.traverse_shortest_winner_count(active) > 0 {
      break
    }
  } nobreak {
    fail("owned winner was not reached")
  }
  assert_true(@bounded.request_cancel(control))
  assert_false(@local_sga.traverse_stopped(active))
  assert_true(@graphs.producer_read_available(input))
  assert_true(
    @local_sga.advance_traverse(active, 1).unwrap()
    is @local_sga.TraverseStopped(_, ..),
  )
  assert_true(@local_sga.traverse_stopped(active))
  assert_true(@local_sga.cleanup_traverse(active).unwrap())
  assert_eq(@local_sga.traverse_shortest_winner_count(active), 0)
  assert_eq(@local_sga.traverse_private_workspace_usage(active).0, 0)
  assert_true(@graphs.producer_read_available(input))
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
}

///|
test "Shortest validates unvisited weights and preserves hop-capped cost selection and atomic overrange" {
  for
    (edge_rows, max_hops, target_list, expected_cost, expected_issue) in [
      (
        "[{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":2,\"cost\":7},{\"key\":11,\"tenant\":\"a\",\"src\":1,\"dst\":3,\"cost\":2},{\"key\":12,\"tenant\":\"a\",\"src\":3,\"dst\":2,\"cost\":2}]",
        1,
        [2],
        Some(7.0),
        None,
      ),
      (
        "[{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":2,\"cost\":7},{\"key\":11,\"tenant\":\"a\",\"src\":1,\"dst\":3,\"cost\":2},{\"key\":12,\"tenant\":\"a\",\"src\":3,\"dst\":2,\"cost\":2}]",
        2,
        [2],
        Some(4.0),
        None,
      ),
      (
        "[{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":2,\"cost\":0},{\"key\":11,\"tenant\":\"a\",\"src\":3,\"dst\":3,\"cost\":-1}]",
        1,
        [2],
        None,
        Some(@local_sga.InvalidShortestCost),
      ),
      (
        "[{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":2,\"cost\":1.7976931348623157e308},{\"key\":11,\"tenant\":\"a\",\"src\":2,\"dst\":3,\"cost\":1.7976931348623157e308}]",
        2,
        [2],
        Some(1.7976931348623157e308),
        None,
      ),
      (
        "[{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":2,\"cost\":1.7976931348623157e308},{\"key\":11,\"tenant\":\"a\",\"src\":2,\"dst\":3,\"cost\":1.7976931348623157e308}]",
        2,
        [2, 3],
        None,
        Some(@local_sga.SelectedShortestOverrange),
      ),
    ] {
    let nodes = keyed_node_source(
      rows="[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"},{\"id\":2,\"tenant\":\"a\",\"name\":\"two\"},{\"id\":3,\"tenant\":\"a\",\"name\":\"three\"}]",
    )
    let edges = keyed_source_owner(
      "{\"key\":{\"type\":\"number\",\"nullable\":false},\"tenant\":{\"type\":\"string\",\"nullable\":false},\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false},\"cost\":{\"type\":\"number\",\"nullable\":false}}",
      edge_rows,
    )
    let graph_owner = keyed_bridge_owner(
      nodes,
      edges,
      body=Some(
        (
          #|[{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["tenant","id"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["tenant","src"]},"target":{"definition":"N","key":["tenant","dst"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"cost","to":"cost"}]}}]}]},"as":"g"}]
        ),
      ),
    )
    let construction = @local_bridge.start_rows_to_graph(
      @bounded.control(),
      prepared_sequence(graph_owner),
      0,
      keyed_bridge_inputs(graph_owner, nodes, edges),
      { ..carrier_graph_storage_limits(), max_work: 100000, },
      65536L,
      1000,
      () => true,
    ).unwrap()
    guard keyed_bridge_terminal(construction)
      is @local_bridge.Complete(graph, ..) else {
      fail("weighted Graph construction")
    }
    guard @pipeline.carrier_at(
        @lower.pipeline(@lower.bound_preparation(graph_owner)),
        @pipeline.Step(0),
      )
      is Some(@carrier_contract.GraphValue(carrier)) else {
      fail("weighted Graph contract")
    }
    let domain = @carrier_contract.graph_domain(
      @carrier_contract.graph_definition(carrier),
    )
    let targets = target_list
      .map(key => traversal_fixture_node(domain, key))
      .join(",")
    let owner = keyed_graph_receiver(
      graph_owner,
      body="[{\"from\":\"g\",\"shortest_path\":{\"source\":" +
        traversal_fixture_node(domain, 1) +
        ",\"target\":{\"ids\":[" +
        targets +
        "]},\"selection\":\"each_pair\",\"direction\":\"out\",\"max_hops\":" +
        max_hops.to_string() +
        ",\"weight\":\"cost\"}}]",
    )
    let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
    let mut reference_work = None
    for quantum in [1, 7, 64] {
      let active = @local_sga.start_traverse_view(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        @graphs.producer_read_view(input).unwrap(),
        target_list.length(),
        {
          max_work: 100000,
          max_nodes: 10000,
          max_text_bytes: 10000,
          max_depth: 50,
        },
        20000,
        10000,
        10000,
        [],
      ).unwrap()
      for _ in 0..<100000 {
        match @local_sga.advance_traverse(active, quantum).unwrap() {
          @local_sga.TraverseContinue(..) => ()
          @local_sga.TraverseComplete(output, work~, ..) => {
            assert_true(expected_issue is None)
            assert_eq(@execution.completed_row_count(output), 1)
            guard @execution.completed_cell(output, 0, 5) is Some(Number(cost)) &&
              @execution.completed_cell(output, 0, 1) is Some(Number(hops)) else {
              fail("typed shortest numeric columns")
            }
            assert_eq(cost, expected_cost.unwrap())
            assert_eq(hops, if expected_cost == Some(4.0) { 2.0 } else { 1.0 })
            if reference_work is Some(expected) {
              assert_eq(work, expected)
            }
            reference_work = Some(work)
            break
          }
          @local_sga.TraverseFailed(
            @local_sga.TraversePathIssue(
              @local_sga.TraversePathsShortest(issue)
            ),
            progress~,
            work~
          ) => {
            assert_eq(Some(issue), expected_issue)
            assert_eq(progress, 0L)
            if reference_work is Some(expected) {
              assert_eq(work, expected)
            }
            reference_work = Some(work)
            break
          }
          _ => fail("unexpected weighted shortest terminal")
        }
      } nobreak {
        fail("finite weighted fixture limit")
      }
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      assert_eq(@local_sga.traverse_private_entry_count(active), 0)
      assert_eq(@local_sga.traverse_private_workspace_usage(active).0, 0)
      assert_true(@graphs.producer_read_available(input))
    }
    assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  }
}
