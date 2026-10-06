///|
fn keyed_relation_path_owner(
  graph : @lower.BoundPrepared,
  selector : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      (
        #|[{"from":"g","traverse":{"start":{"from":"seeds","id":"key"},"path_mode":"trail","hops":[{"direction":"out","edge_types":["R"]},{"direction":"out","edge_types":["R"]}],"emit":"paths"}}]
      ),
    ),
    [
      (
        "g",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(graph)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
      (
        "seeds",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(selector)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn keyed_repeat_selector_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let produced = @pipeline.ProducedInput(
    @pipeline.produced_input(
      @lower.pipeline(@lower.bound_preparation(source)),
      @pipeline.Step(0),
    ).unwrap(),
  )
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"l\",\"append\":{\"with\":\"r\"}}]"),
    [("l", produced), ("r", produced)],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn keyed_repeat_selector_output(
  owner : @lower.BoundPrepared,
  source : @lower.BoundPrepared,
  output : @execution.CompletedOutput,
) -> @execution.CompletedOutput raise {
  let reads = []
  for position in 0..<2 {
    reads.push(
      @execution.prepare_producer_read(
        owner,
        @execution.bind_completed_input(owner, position, source, output).unwrap(),
        100,
        10000,
      ).unwrap(),
    )
  }
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  let run = @execution.start_bounded_append(
    @bounded.control(),
    task_test_generated(owner),
    reads[0],
    reads[1],
    10,
    limits,
    limits,
    100000,
    1000,
    10000,
    10000,
  ).unwrap()
  for _ in 0..<100000 {
    match @execution.advance_bounded_append(run, 1).unwrap() {
      @execution.BoundedAppendContinue(..) => ()
      @execution.BoundedAppendComplete(result, ..) => {
        assert_true(@execution.cleanup_bounded_append(run).unwrap())
        return result
      }
      _ => fail("bounded selector append failed")
    }
  }
  fail("bounded selector append exceeded fixture work allowance")
}

///|
test "keyed TRAIL retains exact Graph and Relation selector owners through stop and completion" {
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
    fail("constructor failed")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(contract)) else {
    fail("current Graph definition missing")
  }
  let domain = @carrier_contract.property_graph_domain(
    @carrier_contract.graph_property_definition(contract),
  )
  // Expected identity and trails come from the admitted definition and fixture
  // keys. The actual selector runs keyed MATCH then the existing bounded APPEND;
  // it does not fabricate a JSON VALUES producer or a trusted completion.
  let identity = "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[\"a\",1],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}"
  for empty in [false, true] {
    let seed_owner = keyed_graph_receiver(
      graph_owner,
      body="[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"key\"},\"where\":\"" +
        (if empty { "false" } else { "true" }) +
        "\",\"fields\":[\"key\"]}}]",
    )
    let seed_read = @graphs.prepare_producer_read(
      seed_owner, 0, graph_owner, graph,
    ).unwrap()
    let seed_run = @local_sga.start_match_nodes(
      @bounded.control(),
      task_test_completion(seed_owner),
      prepared_sequence(seed_owner),
      0,
      seed_read,
      10,
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
    let seed_output = finish_match_nodes(seed_run).unwrap()
    assert_eq(
      @execution.completed_row_count(seed_output),
      if empty {
        0
      } else {
        1
      },
    )
    if !empty {
      assert_eq(
        @execution.completed_output_row_wire(seed_output, 0, 10000, 10000, 50).unwrap(),
        "{\"key\":" + property_graph_expected_json_wire(identity) + "}",
      )
    }
    assert_true(@local_sga.cleanup_match_nodes(seed_run).unwrap())
    let selector_owner = keyed_repeat_selector_owner(seed_owner)
    let selector_output = keyed_repeat_selector_output(
      selector_owner, seed_owner, seed_output,
    )
    let owner = keyed_relation_path_owner(graph_owner, selector_owner)
    let foreign = keyed_relation_path_owner(graph_owner, selector_owner)
    let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
    let selector = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, selector_owner, selector_output).unwrap(),
      100,
      1000,
    ).unwrap()
    let foreign_selector = @execution.prepare_producer_read(
      foreign,
      @execution.bind_completed_input(
        foreign, 1, selector_owner, selector_output,
      ).unwrap(),
      100,
      1000,
    ).unwrap()
    let preparation = task_test_completion(owner)
    for viewed in [false, true] {
      let start = fn(control, relations, work, workspace) {
        let limits : @execution.ValueLimits = {
          max_work: work,
          max_nodes: 10000,
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
            10,
            limits,
            workspace,
            10000,
            10000,
            relations,
          )
        } else {
          @local_sga.start_traverse(
            control,
            preparation,
            prepared_sequence(owner),
            0,
            input,
            10,
            limits,
            workspace,
            10000,
            10000,
            relations,
          )
        }
      }
      assert_true(start(@bounded.control(), [], 100000, 20000) is Err(_))
      assert_true(
        start(@bounded.control(), [foreign_selector], 100000, 20000) is Err(_),
      )
      let active = start(@bounded.control(), [selector], 100000, 20000).unwrap()
      let output = finish_traverse(active).unwrap()
      // Two distinct parallel edges permit exactly the ordered trails [10,11]
      // and [11,10]. Duplicate selector rows do not duplicate either trail.
      assert_eq(
        @execution.completed_row_count(output),
        if empty {
          0
        } else {
          2
        },
      )
      for row in 0..<(if empty { 0 } else { 2 }) {
        let edge = fn(key : Int) {
          "{\"definition\":\"E\",\"domain\":\"" +
          domain +
          "\",\"key\":[" +
          key.to_string() +
          "],\"key_types\":[{\"kind\":\"number\"}]}"
        }
        let expected = "{\"edge_ids\":[" +
          property_graph_expected_json_wire(edge(10 + row)) +
          "," +
          property_graph_expected_json_wire(edge(11 - row)) +
          "],\"end_id\":" +
          property_graph_expected_json_wire(identity) +
          ",\"hop_count\":2,\"node_ids\":[" +
          property_graph_expected_json_wire(identity) +
          "," +
          property_graph_expected_json_wire(identity) +
          "," +
          property_graph_expected_json_wire(identity) +
          "],\"start_id\":" +
          property_graph_expected_json_wire(identity) +
          "}"
        assert_eq(
          @execution.completed_output_row_wire(output, row, 10000, 10000, 50).unwrap(),
          expected,
        )
      }
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.traverse_cleanup_pending(active))
      assert_true(@execution.completed_output_available(output))
      assert_true(@execution.producer_read_available(selector))
      assert_true(@graphs.producer_read_available(input))
      let control = @bounded.control()
      let cancelled = start(control, [selector], 100000, 20000).unwrap()
      assert_true(
        @local_sga.advance_traverse(cancelled, 1)
        is Ok(@local_sga.TraverseContinue(..)),
      )
      assert_true(@bounded.request_cancel(control))
      assert_true(
        @local_sga.advance_traverse(cancelled, 1)
        is Ok(@local_sga.TraverseStopped(_, ..)),
      )
      assert_true(@local_sga.cleanup_traverse(cancelled).unwrap())
      assert_false(@local_sga.cleanup_traverse(cancelled).unwrap())
      assert_false(@local_sga.traverse_cleanup_pending(cancelled))
      assert_eq(@local_sga.traverse_private_entry_count(cancelled), 0)
      assert_true(@execution.producer_read_available(selector))
      assert_true(@graphs.producer_read_available(input))
      if empty {
        // One node slot is initialized and collected; Finish charges one.
        // No selector row, predicate or path expansion is evaluated: exactly
        // three control units and one slot, independently of measured output.
        assert_true(
          start(@bounded.control(), [selector], 3, 0)
          is Err(
            @local_sga.TraversePathIssue(@local_sga.TraversePathsWorkspaceLimit)
          ),
        )
        let exact = start(@bounded.control(), [selector], 3, 1).unwrap()
        let spent = Ref(0L)
        assert_eq(
          @execution.completed_row_count(
            finish_traverse(exact, spent_work=Some(spent)).unwrap(),
          ),
          0,
        )
        assert_eq(spent.val, 3L)
        assert_true(@local_sga.cleanup_traverse(exact).unwrap())
        let short = start(@bounded.control(), [selector], 2, 1).unwrap()
        assert_true(
          finish_traverse(short, spent_work=Some(spent))
          is Err(
            @local_sga.TraversePathIssue(@local_sga.TraversePathsWorkLimit)
          ),
        )
        assert_eq(spent.val, 2L)
        assert_true(@local_sga.cleanup_traverse(short).unwrap())
        assert_eq(@local_sga.traverse_private_entry_count(short), 0)
        for prefix in 0..<3 {
          let stop_control = @bounded.control()
          let stopping = start(stop_control, [selector], 3, 1).unwrap()
          for index in 0..<prefix {
            guard @local_sga.advance_traverse(stopping, 1)
              is Ok(@local_sga.TraverseContinue(work~, ..)) else {
              fail("private path step did not yield")
            }
            assert_eq(work, (index + 1).to_int64())
          }
          assert_true(@bounded.request_cancel(stop_control))
          guard @local_sga.advance_traverse(stopping, 1)
            is Ok(@local_sga.TraverseStopped(_, work~, ..)) else {
            fail("cancelled path did not stop")
          }
          assert_eq(work, prefix.to_int64())
          assert_true(@local_sga.cleanup_traverse(stopping).unwrap())
          assert_false(@local_sga.cleanup_traverse(stopping).unwrap())
          assert_false(@local_sga.traverse_cleanup_pending(stopping))
          assert_eq(@local_sga.traverse_private_entry_count(stopping), 0)
          assert_true(@execution.producer_read_available(selector))
          assert_true(@graphs.producer_read_available(input))
        }
      }
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
