///|
test "long literal and Relation selectors yield before output and retain borrowed custody" {
  let key = "x".repeat(160) + "🌙"
  let source = keyed_source_owner(
    "{\"id\":{\"type\":\"string\",\"nullable\":false}}",
    "[{\"id\":\"" + key + "\"}]",
  )
  let graph_body =
    #|[{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"]}],"edges":[{"name":"E","from":"edges","key":["id"],"source":{"definition":"N","key":["id"]},"target":{"definition":"N","key":["id"]}}]},"as":"g"}]
  let graph_owner = keyed_bridge_owner(source, source, body=Some(graph_body))
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, source, source),
    { ..carrier_graph_storage_limits(), max_work: 100000, },
    10000L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction, max_fixture_steps=100000)
    is @local_bridge.Complete(graph, ..) else {
    fail("long-key Graph construction")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(carrier)) else {
    fail("Graph carrier")
  }
  let domain = @carrier_contract.graph_domain(
    @carrier_contract.graph_definition(carrier),
  )
  let identity = "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[\"" +
    key +
    "\"],\"key_types\":[{\"kind\":\"string\"}]}"
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  let seeds = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"key\"},\"where\":\"true\",\"fields\":[\"key\"]}}]",
  )
  let seed_read = @graphs.prepare_producer_read(seeds, 0, graph_owner, graph).unwrap()
  let seed_run = @local_sga.start_match_nodes(
    @bounded.control(),
    task_test_completion(seeds),
    prepared_sequence(seeds),
    0,
    seed_read,
    1,
    limits,
    20000,
    10000,
    10000,
    [],
  ).unwrap()
  let seed_output = finish_match_nodes(seed_run).unwrap()
  assert_true(@local_sga.cleanup_match_nodes(seed_run).unwrap())
  for relation in [false, true] {
    let owner = if relation {
      keyed_relation_path_owner(
        graph_owner,
        seeds,
        body="[{\"from\":\"g\",\"reach\":{\"start\":{\"from\":\"seeds\",\"id\":\"key\"},\"direction\":\"out\",\"max_depth\":1}}]",
      )
    } else {
      keyed_graph_receiver(
        graph_owner,
        body="[{\"from\":\"g\",\"reach\":{\"start\":" +
          identity +
          ",\"direction\":\"out\",\"max_depth\":1}}]",
      )
    }
    let graph_read = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
    let inputs = if relation {
      [
        @execution.prepare_producer_read(
          owner,
          @execution.bind_completed_input(owner, 1, seeds, seed_output).unwrap(),
          100,
          10000,
        ).unwrap(),
      ]
    } else {
      []
    }
    let preparation = task_test_completion(owner)
    let start = fn(control) {
      @local_sga.start_traverse_view(
        control,
        preparation,
        prepared_sequence(owner),
        0,
        @graphs.producer_read_view(graph_read).unwrap(),
        1,
        limits,
        20000,
        10000,
        10000,
        inputs,
      ).unwrap()
    }
    let mut reference_work = None
    for quantum in [1, 7, 256] {
      let run = start(@bounded.control())
      let spent = Ref(0L)
      let result = finish_traverse(run, quantum~, spent_work=Some(spent)).unwrap()
      // The two Unicode scalar walks and UTF-16 comparison of this authored
      // key alone require at least three polls per ASCII prefix character.
      // Synchronous key lookup charged as one tick cannot meet this lower bound.
      assert_true(spent.val >= (3 * 160).to_int64())
      match reference_work {
        None => reference_work = Some(spent.val)
        Some(work) => assert_eq(work, spent.val)
      }
      assert_eq(@execution.completed_row_count(result), 1)
      assert_eq(
        @execution.completed_output_row_wire(result, 0, 10000, 10000, 50).unwrap(),
        "{\"depth\":0,\"node_id\":" +
        graph_expected_json_wire(identity) +
        ",\"start_id\":" +
        graph_expected_json_wire(identity) +
        "}",
      )
      assert_true(@local_sga.cleanup_traverse(run).unwrap())
      assert_eq(@local_sga.traverse_private_entry_count(run), 0)
    }
    // One stop is inside identity admission, the next inside the first long
    // identity comparison. Neither has begun output-field preparation.
    for prefix in [10, 40] {
      let control = @bounded.control()
      let run = start(control)
      for index in 0..<prefix {
        assert_true(
          @local_sga.advance_traverse(run, 1)
          is Ok(@local_sga.TraverseContinue(work~, ..)) &&
          work == (index + 1).to_int64(),
        )
      }
      assert_eq(@local_sga.traverse_value_item_attempts(run), 0)
      assert_true(@bounded.request_cancel(control))
      assert_true(
        @local_sga.advance_traverse(run, 1)
        is Ok(@local_sga.TraverseStopped(_, ..)),
      )
      assert_true(@local_sga.cleanup_traverse(run).unwrap())
      assert_false(@local_sga.cleanup_traverse(run).unwrap())
      assert_eq(@local_sga.traverse_private_entry_count(run), 0)
      assert_eq(@local_sga.traverse_private_workspace_usage(run).0, 0)
      assert_true(@graphs.producer_read_available(graph_read))
      for input in inputs {
        assert_true(@execution.producer_read_available(input))
      }
      assert_true(@execution.completed_output_available(seed_output))
    }
  }
}
