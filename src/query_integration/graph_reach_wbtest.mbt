///|
test "Reach typed selectors preserve depth zero minimum depth and bounded predicate work" {
  let nodes = keyed_node_source(
    rows="[{\"id\":3,\"tenant\":\"a\",\"name\":\"three\"},{\"id\":2,\"tenant\":\"a\",\"name\":\"two\"},{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"}]",
  )
  let edges = keyed_edge_source(
    rows="[{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":2},{\"key\":11,\"tenant\":\"a\",\"src\":1,\"dst\":2},{\"key\":12,\"tenant\":\"a\",\"src\":2,\"dst\":3},{\"key\":13,\"tenant\":\"a\",\"src\":1,\"dst\":3},{\"key\":14,\"tenant\":\"a\",\"src\":3,\"dst\":1},{\"key\":15,\"tenant\":\"a\",\"src\":1,\"dst\":1}]",
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
  guard keyed_bridge_terminal(construction, max_fixture_steps=10000)
    is @local_bridge.Complete(graph, ..) else {
    fail("Graph construction failed")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(carrier)) else {
    fail("Graph schema")
  }
  let domain = @carrier_contract.graph_domain(
    @carrier_contract.graph_definition(carrier),
  )
  let identity = traversal_fixture_node(domain, 1)
  for
    (start, expected, predicate_count) in [
      (identity, [(1, 1, 0), (1, 2, 1), (1, 3, 1)], 0),
      (
        "{\"ids\":[" + identity + "," + identity + "]}",
        [(1, 1, 0), (1, 2, 1), (1, 3, 1)],
        0,
      ),
      ("{\"where\":\"display = 'one'\"}", [(1, 1, 0), (1, 2, 1), (1, 3, 1)], 3),
      ("{\"where\":\"false\"}", [], 3),
    ] {
    let owner = keyed_graph_receiver(
      graph_owner,
      body="[{\"from\":\"g\",\"reach\":{\"start\":" +
        start +
        ",\"direction\":\"out\",\"max_depth\":2}}]",
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
        expected.length(),
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
      let mut output = None
      for _ in 0..<10000 {
        match @local_sga.advance_traverse(active, quantum).unwrap() {
          @local_sga.TraverseContinue(work=w, ..) => {
            assert_true(w >= work && w - work <= quantum.to_int64())
            work = w
          }
          @local_sga.TraverseComplete(result, work=w, ..) => {
            assert_true(w >= work && w - work <= quantum.to_int64())
            work = w
            output = Some(result)
            break
          }
          @local_sga.TraverseFailed(issue, ..) => {
            assert_eq(Some(issue), None)
            fail("Reach kernel failed")
          }
          _ => fail("Reach stopped unexpectedly")
        }
      } nobreak {
        fail("Reach did not settle")
      }
      match reference_work {
        None => reference_work = Some(work)
        Some(expected_work) => assert_eq(work, expected_work)
      }
      assert_eq(@local_sga.traverse_predicate_starts(active), predicate_count)
      let output = output.unwrap()
      assert_eq(@execution.completed_row_count(output), expected.length())
      for row, (start, node, depth) in expected {
        assert_eq(
          @execution.completed_output_row_wire(output, row, 10000, 10000, 50).unwrap(),
          "{\"depth\":" +
          depth.to_string() +
          ",\"node_id\":" +
          graph_expected_json_wire(traversal_fixture_node(domain, node)) +
          ",\"start_id\":" +
          graph_expected_json_wire(traversal_fixture_node(domain, start)) +
          "}",
        )
      }
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.cleanup_traverse(active).unwrap())
      assert_eq(@local_sga.traverse_private_entry_count(active), 0)
      assert_true(@execution.completed_output_available(output))
      assert_true(@graphs.producer_read_available(input))
    }
    if predicate_count > 0 {
      let control = @bounded.control()
      let active = @local_sga.start_traverse_view(
        control,
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        @graphs.producer_read_view(input).unwrap(),
        expected.length(),
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
      for _ in 0..<10000 {
        assert_true(
          @local_sga.advance_traverse(active, 1).unwrap()
          is @local_sga.TraverseContinue(..),
        )
        if @local_sga.traverse_predicate_starts(active) > 0 {
          break
        }
      } nobreak {
        fail("Reach did not enter its start predicate")
      }
      assert_true(@bounded.request_cancel(control))
      assert_true(@graphs.producer_read_available(input))
      assert_true(
        @local_sga.advance_traverse(active, 1).unwrap()
        is @local_sga.TraverseStopped(@bounded.Cancelled, ..),
      )
      assert_true(@local_sga.traverse_stopped(active))
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.cleanup_traverse(active).unwrap())
      assert_eq(@local_sga.traverse_private_entry_count(active), 0)
      assert_true(@graphs.producer_read_available(input))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "Reach Relation starts recheck nonnull identities and reject NULL or absent membership" {
  let nodes = keyed_node_source()
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
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(carrier)) else {
    fail("Graph schema")
  }
  let domain = @carrier_contract.graph_domain(
    @carrier_contract.graph_definition(carrier),
  )
  for
    (key, rows, error, expected_rows) in [
      (1, "[{\"keep\":true}]", None, 1),
      (1, "[]", None, 0),
      (
        1,
        "[{\"keep\":false}]",
        Some(@local_sga.TraversePathsKeyOrder(@admitted.InvalidKey)),
        0,
      ),
      (99, "[{\"keep\":true}]", Some(@local_sga.TraversePathsStartMissing), 0),
    ] {
    let writer = @encode.writer(10000, 1000, 100)
    @encode.string_value(writer, traversal_fixture_node(domain, key))
    let selector_owner = keyed_source_owner(
      "{\"keep\":{\"type\":\"boolean\",\"nullable\":false}}",
      rows,
      suffix=",{\"derive\":{\"key\":{\"case\":{\"when\":[{\"when\":{\"field\":\"keep\"},\"then\":{\"typed_literal\":{\"type\":\"json\",\"value\":" +
        @encode.finish(writer) +
        "}}}]}}}}",
    )
    let selector_result = @execution.execute_generated_sequence(
      task_test_generated(selector_owner),
      [],
      compute_test_limits(),
    ).unwrap()
    let selector_output = @execution.completed_output(
      selector_result,
      @pipeline.Step(1),
    ).unwrap()
    let owner = keyed_relation_path_owner(
      graph_owner,
      selector_owner,
      selector_step=1,
      body="[{\"from\":\"g\",\"reach\":{\"start\":{\"from\":\"seeds\",\"id\":\"key\"},\"direction\":\"both\",\"max_depth\":1}}]",
    )
    let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
    let selector = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, selector_owner, selector_output).unwrap(),
      100,
      10000,
    ).unwrap()
    let active = @local_sga.start_traverse_view(
      @bounded.control(),
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      @graphs.producer_read_view(input).unwrap(),
      1,
      {
        max_work: 100000,
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 50,
      },
      10000,
      10000,
      10000,
      [selector],
    ).unwrap()
    let outcome = finish_traverse(active, quantum=1)
    match error {
      None => {
        let output = outcome.unwrap()
        assert_eq(@execution.completed_row_count(output), expected_rows)
        if expected_rows == 1 {
          let id = graph_expected_json_wire(traversal_fixture_node(domain, 1))
          assert_eq(
            @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
            "{\"depth\":0,\"node_id\":" + id + ",\"start_id\":" + id + "}",
          )
        }
      }
      Some(issue) =>
        assert_eq(outcome.unwrap_err(), @local_sga.TraversePathIssue(issue))
    }
    assert_true(@local_sga.cleanup_traverse(active).unwrap())
    assert_false(@local_sga.cleanup_traverse(active).unwrap())
    assert_eq(@local_sga.traverse_private_entry_count(active), 0)
    assert_true(@graphs.producer_read_available(input))
    assert_true(@execution.producer_read_available(selector))
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "Reach independently counts exact work workspace and every pending handoff cancellation" {
  let nodes = keyed_node_source()
  let edge_count = 100
  let rows : Array[String] = []
  for key in 0..<edge_count {
    rows.push(
      "{\"key\":" + key.to_string() + ",\"tenant\":\"a\",\"src\":1,\"dst\":1}",
    )
  }
  let edges = keyed_edge_source(rows="[" + rows.join(",") + "]")
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    {
      ..carrier_graph_storage_limits(),
      max_input_rows: 200,
      max_edges: edge_count,
      max_work: 1000000,
      max_workspace_slots: 10000,
      max_total_value_bytes: 100000,
      max_retained_value_bytes: 100000,
    },
    1048576L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction, max_fixture_steps=100000)
    is @local_bridge.Complete(graph, ..) else {
    fail("Graph construction failed")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(carrier)) else {
    fail("Graph schema")
  }
  let id = traversal_fixture_node(
    @carrier_contract.graph_domain(@carrier_contract.graph_definition(carrier)),
    1,
  )
  let owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"reach\":{\"start\":" +
      id +
      ",\"direction\":\"both\",\"max_depth\":1}}]",
  )
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  // One selected start: select/resolve/collect (3), depth (1), endpoint (1),
  // three scalar fields (3), row commit (1), completion handoff (1).
  // Both directions scan each self-loop twice. The outgoing occurrence
  // charges one seed membership check; traversal_neighbor rejects the
  // duplicate incoming self-loop before that check (from == to).
  // Three row reads, two complete two-component identity rechecks (32 each),
  // a number recheck, three terminal polls, and charge setup. Logical charge
  // polls are three names/values, two identity trees (24 each), and commit.
  let row_control = 3 + 2 * 32 + 1 + 3 + 1 + (6 + 2 * 24 + 1)
  // Literal admission adds 32 identity-tree polls, one terminal recheck
  // poll, and one separate membership-lookup transition.
  let control_work = 3 +
    32 +
    1 +
    1 +
    1 +
    1 +
    3 +
    1 +
    1 +
    (2 + 1) * edge_count +
    row_control
  // Retained row: row wrapper + one number + two 11-node identities. Text
  // is each identity's fixed 50 bytes and 71-byte domain plus output names.
  let output_work = 1 + 1 + 2 * 11 + 2 * (50 + 71) + (5 + 7 + 8)
  let exact_work = control_work + output_work
  // Seed scanning peaks at five slots. It is released before row emission,
  // leaving start/depth/endpoint indices (3), row buffer (4), frames (3).
  let exact_workspace = 3 + 4 + 3
  let preparation = task_test_completion(owner)
  let start = fn(control, work, workspace) {
    @local_sga.start_traverse_view(
      control,
      preparation,
      prepared_sequence(owner),
      0,
      @graphs.producer_read_view(input).unwrap(),
      1,
      { max_work: work, max_nodes: 1000, max_text_bytes: 10000, max_depth: 50, },
      workspace,
      10000,
      10000,
      [],
      max_paths=1,
    ).unwrap()
  }
  for quantum in [1, 7, 64] {
    let active = start(@bounded.control(), exact_work, exact_workspace)
    let spent = Ref(0L)
    let finished = finish_traverse(active, quantum~, spent_work=Some(spent))
    assert_eq(finished.map(_ => true), Ok(true))
    let output = finished.unwrap()
    assert_eq(spent.val, control_work.to_int64())
    assert_eq(@execution.completed_row_count(output), 1)
    assert_eq(
      @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
      "{\"depth\":0,\"node_id\":" +
      graph_expected_json_wire(id) +
      ",\"start_id\":" +
      graph_expected_json_wire(id) +
      "}",
    )
    assert_true(@local_sga.cleanup_traverse(active).unwrap())
    for
      (work, workspace, expected) in [
        (exact_work - 1, exact_workspace, @local_sga.TraversePathsWorkLimit),
        (
          exact_work,
          exact_workspace - 1,
          @local_sga.TraversePathsWorkspaceLimit,
        ),
      ] {
      let rejected = start(@bounded.control(), work, workspace)
      assert_eq(
        finish_traverse(rejected, quantum~).unwrap_err(),
        @local_sga.TraversePathIssue(expected),
      )
      assert_true(@local_sga.cleanup_traverse(rejected).unwrap())
      assert_false(@local_sga.cleanup_traverse(rejected).unwrap())
      assert_eq(@local_sga.traverse_private_entry_count(rejected), 0)
      assert_true(@graphs.producer_read_available(input))
    }
  }
  for prefix in 0..<control_work {
    let control = @bounded.control()
    let active = start(control, exact_work, exact_workspace)
    for index in 0..<prefix {
      assert_true(
        @local_sga.advance_traverse(active, 1)
        is Ok(@local_sga.TraverseContinue(work=spent, ..)) &&
        spent == (index + 1).to_int64(),
      )
    }
    assert_true(@bounded.request_cancel(control))
    assert_true(
      @local_sga.advance_traverse(active, 1)
      is Ok(@local_sga.TraverseStopped(_, work=spent, ..)) &&
      spent == prefix.to_int64(),
    )
    assert_true(@local_sga.traverse_stopped(active))
    assert_true(@graphs.producer_read_available(input))
    assert_true(@local_sga.cleanup_traverse(active).unwrap())
    assert_false(@local_sga.cleanup_traverse(active).unwrap())
    assert_eq(@local_sga.traverse_private_entry_count(active), 0)
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
