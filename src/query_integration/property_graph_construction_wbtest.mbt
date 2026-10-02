///|
fn keyed_source_owner(schema : String, rows : String) -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":" +
      schema +
      ",\"rows\":" +
      rows +
      "},\"as\":\"source\"}]",
    ),
    [],
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
fn keyed_node_source(
  rows? : String = "[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"},{\"id\":null,\"tenant\":\"a\",\"name\":\"excluded\"}]",
) -> @lower.BoundPrepared {
  keyed_source_owner(
    (
      #|{"id":{"type":"number","nullable":true},"tenant":{"type":"string","nullable":false},"name":{"type":"string","nullable":false}}
    ),
    rows,
  )
}

///|
fn keyed_edge_source(
  rows? : String = "[{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":1},{\"key\":11,\"tenant\":\"a\",\"src\":1,\"dst\":1},{\"key\":null,\"tenant\":\"a\",\"src\":1,\"dst\":1},{\"key\":12,\"tenant\":\"a\",\"src\":1,\"dst\":9}]",
) -> @lower.BoundPrepared {
  keyed_source_owner(
    (
      #|{"key":{"type":"number","nullable":true},"tenant":{"type":"string","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}}
    ),
    rows,
  )
}

///|
fn keyed_bridge_owner(
  nodes : @lower.BoundPrepared,
  edges : @lower.BoundPrepared,
  body? : String? = None,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      body.unwrap_or(
        (
          #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["tenant","id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"name","to":"display"}]}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["tenant","src"]},"target":{"definition":"N","key":["tenant","dst"]},"labels":[{"name":"R","properties":{"mode":"no_properties"}}]}]},"as":"g"}]
        ),
      ),
    ),
    [
      (
        "nodes",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(nodes)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
      (
        "edges",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(edges)),
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
fn keyed_bridge_inputs(
  owner : @lower.BoundPrepared,
  nodes : @lower.BoundPrepared,
  edges : @lower.BoundPrepared,
) -> Array[@execution.ProducerRead] raise {
  let inputs = []
  for index, source in [nodes, edges] {
    let output = carrier_events_source_output(source)
    inputs.push(
      @execution.prepare_producer_read(
        owner,
        @execution.bind_completed_input(owner, index, source, output).unwrap(),
        1000,
        10000,
      ).unwrap(),
    )
  }
  inputs
}

///|
fn keyed_bridge_terminal(
  active : @local_bridge.RowsToGraphExecution,
) -> @local_bridge.RowsToGraphPoll {
  for _ in 0..<1000 {
    match @local_bridge.advance_rows_to_graph(active, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      terminal => return terminal
    }
  }
  abort("bounded property constructor did not finish")
}

///|
fn keyed_graph_receiver(
  owner : @lower.BoundPrepared,
  body? : String = "[]",
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(body),
    [
      (
        "g",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(owner)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"g\"")),
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
test "keyed MATCH reuses typed predicates and retains independent parallel edge identities" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source(
    rows="[{\"key\":11,\"tenant\":\"a\",\"src\":1,\"dst\":1},{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":1}]",
  )
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
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
    is Some(@carrier_contract.GraphValue(carrier)) else {
    fail("Graph schema")
  }
  let domain = @carrier_contract.property_graph_domain(
    @carrier_contract.graph_property_definition(carrier),
  )
  let node_id = "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[\"a\",1],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}"
  for viewed in [false, true] {
    for
      (nodes_match, body, count) in [
        (
          true, "[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"label\":\"node\",\"bindings\":{\"identity\":\"element\"},\"where\":\"display = 'one'\",\"fields\":[\"display\",\"element\"]}}]",
          1,
        ),
        (
          false, "[{\"from\":\"g\",\"match_edges\":{\"definition\":\"E\",\"types\":[\"r\"],\"bindings\":{\"identity\":\"element\",\"source\":\"from_node\",\"target\":\"to_node\"},\"fields\":[\"element\",\"from_node\",\"to_node\"]}}]",
          2,
        ),
        (
          false, "[{\"from\":\"g\",\"match_edges\":{\"definition\":\"E\",\"types\":[\"key\"],\"bindings\":{\"identity\":\"element\"},\"fields\":[\"element\"]}}]",
          0,
        ),
      ] {
      let owner = keyed_graph_receiver(graph_owner, body~)
      let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
      let sequence = prepared_sequence(owner)
      let limits : @execution.ValueLimits = {
        max_work: 100000,
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 50,
      }
      let output = if nodes_match {
        let active = if viewed {
          @local_sga.start_match_nodes_view(
            @bounded.control(),
            task_test_completion(owner),
            sequence,
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
          @local_sga.start_match_nodes(
            @bounded.control(),
            task_test_completion(owner),
            sequence,
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
        let output = finish_match_nodes(active).unwrap()
        assert_true(@local_sga.cleanup_match_nodes(active).unwrap())
        assert_false(@local_sga.cleanup_match_nodes(active).unwrap())
        assert_false(@local_sga.match_nodes_cleanup_pending(active))
        output
      } else {
        let active = if viewed {
          @local_sga.start_match_edges_view(
            @bounded.control(),
            task_test_completion(owner),
            sequence,
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
          @local_sga.start_match_edges(
            @bounded.control(),
            task_test_completion(owner),
            sequence,
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
        let output = finish_match_edges(active).unwrap()
        assert_true(@local_sga.cleanup_match_edges(active).unwrap())
        assert_false(@local_sga.cleanup_match_edges(active).unwrap())
        assert_false(@local_sga.match_edges_cleanup_pending(active))
        output
      }
      assert_eq(@execution.completed_row_count(output), count)
      for row in 0..<count {
        let expected = if nodes_match {
          "{\"display\":\"one\",\"element\":" + node_id + "}"
        } else {
          let edge_id = "{\"definition\":\"E\",\"domain\":\"" +
            domain +
            "\",\"key\":[" +
            (row + 10).to_string() +
            "],\"key_types\":[{\"kind\":\"number\"}]}"
          "{\"element\":" +
          edge_id +
          ",\"from_node\":" +
          node_id +
          ",\"to_node\":" +
          node_id +
          "}"
        }
        assert_eq(
          @execution.completed_output_row_wire(output, row, 10000, 10000, 50).unwrap(),
          expected,
        )
      }
      assert_true(@execution.completed_output_available(output))
      assert_true(@graphs.producer_read_available(input))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "keyed node MATCH preserves exact work workspace and every private stop boundary" {
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
  let owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"where\":\"true\",\"fields\":[\"display\"]}}]",
  )
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let sequence = prepared_sequence(owner)
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  // One retained node: two sort entries plus one output column. A literal
  // true selector costs scratch + resolve + read + commit + finish = 5.
  // These constants come from the fixture and phases, not a measured run.
  let workspace = 2 * 1 + 1
  let work = 1 + 1 + 1 + 1 + 1
  let preparation = task_test_completion(owner)
  for viewed in [false, true] {
    let start = fn(control, slots, allowed_work, maximum) {
      if viewed {
        @local_sga.start_match_nodes_view(
          control,
          preparation,
          sequence,
          0,
          @graphs.producer_read_view(input).unwrap(),
          maximum,
          limits,
          slots,
          10000,
          10000,
          [],
          control_work_limit=Some(allowed_work),
        )
      } else {
        @local_sga.start_match_nodes(
          control,
          preparation,
          sequence,
          0,
          input,
          maximum,
          limits,
          slots,
          10000,
          10000,
          [],
          control_work_limit=Some(allowed_work),
        )
      }
    }
    assert_true(
      start(@bounded.control(), workspace - 1, work, 1)
      is Err(@local_sga.MatchNodesWorkspaceLimit),
    )
    for quantum in [1, 7] {
      for (allowed, maximum) in [(work, 1), (work - 1, 1), (work, 0)] {
        let active = start(@bounded.control(), workspace, allowed, maximum).unwrap()
        let mut terminal = false
        for _ in 0..<20 {
          match @local_sga.advance_match_nodes(active, quantum).unwrap() {
            @local_sga.MatchNodesContinue(..) => ()
            @local_sga.MatchNodesComplete(output, work=spent, ..) => {
              assert_eq(allowed, work)
              assert_eq(maximum, 1)
              assert_eq(spent, work.to_int64())
              assert_eq(@execution.completed_row_count(output), 1)
              assert_true(
                @execution.completed_cell(output, 0, 0) is Some(Text("one")),
              )
              terminal = true
              break
            }
            @local_sga.MatchNodesFailed(
              @local_sga.MatchNodesWorkLimit,
              work=spent,
              ..
            ) => {
              assert_eq(allowed, work - 1)
              assert_eq(spent, allowed.to_int64())
              terminal = true
              break
            }
            @local_sga.MatchNodesFailed(
              @local_sga.MatchNodesOutput(@execution.CaptureLimit),
              ..
            ) => {
              assert_eq(maximum, 0)
              terminal = true
              break
            }
            _ =>
              fail(
                "MATCH must preserve the exact limit and never publish a partial result",
              )
          }
        }
        assert_true(terminal)
        assert_true(@local_sga.match_nodes_cleanup_pending(active))
        assert_true(@local_sga.cleanup_match_nodes(active).unwrap())
        assert_false(@local_sga.cleanup_match_nodes(active).unwrap())
        assert_false(@local_sga.match_nodes_cleanup_pending(active))
        assert_eq(@local_sga.match_nodes_scratch_slots(active), 0)
        assert_true(@graphs.producer_read_available(input))
      }
    }
    // Stop at every quantum-one yield before public completion, including
    // after a private row has been committed but before final publication.
    for prefix in 0..<work {
      let control = @bounded.control()
      let active = start(control, workspace, work, 1).unwrap()
      for _ in 0..<prefix {
        assert_true(
          @local_sga.advance_match_nodes(active, 1)
          is Ok(@local_sga.MatchNodesContinue(..)),
        )
      }
      assert_true(@bounded.request_cancel(control))
      guard @local_sga.advance_match_nodes(active, 1)
        is Ok(@local_sga.MatchNodesStopped(_, work=spent, ..)) else {
        fail("cancelled MATCH must not hand off private output")
      }
      assert_eq(spent, prefix.to_int64())
      assert_true(@local_sga.match_nodes_stopped(active))
      assert_true(@local_sga.cleanup_match_nodes(active).unwrap())
      assert_false(@local_sga.cleanup_match_nodes(active).unwrap())
      assert_false(@local_sga.match_nodes_cleanup_pending(active))
      assert_eq(@local_sga.match_nodes_scratch_slots(active), 0)
      assert_true(@local_sga.advance_match_nodes(active, 1) is Err(_))
      assert_true(@graphs.producer_read_available(input))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "keyed edge MATCH preserves exact work workspace and every private stop boundary" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source(
    rows="[{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":1}]",
  )
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
    is Some(@carrier_contract.GraphValue(carrier)) else {
    fail("Graph schema")
  }
  let domain = @carrier_contract.property_graph_domain(
    @carrier_contract.graph_property_definition(carrier),
  )
  let expected = "{\"key\":{\"definition\":\"E\",\"domain\":\"" +
    domain +
    "\",\"key\":[10],\"key_types\":[{\"kind\":\"number\"}]}}"
  let owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"key\"},\"fields\":[\"key\"]}}]",
  )
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let sequence = prepared_sequence(owner)
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  // One retained edge: two sort entries plus one output column. Without
  // a predicate, scratch + select + read + commit + finish costs 5.
  // These constants come from the fixture and phases, not a measured run.
  let workspace = 2 * 1 + 1
  let work = 1 + 1 + 1 + 1 + 1
  let retained : Array[@execution.CompletedOutput] = []
  let preparation = task_test_completion(owner)
  for viewed in [false, true] {
    let start = fn(control, slots, allowed_work, maximum) {
      if viewed {
        @local_sga.start_match_edges_view(
          control,
          preparation,
          sequence,
          0,
          @graphs.producer_read_view(input).unwrap(),
          maximum,
          limits,
          slots,
          10000,
          10000,
          [],
          control_work_limit=Some(allowed_work),
        )
      } else {
        @local_sga.start_match_edges(
          control,
          preparation,
          sequence,
          0,
          input,
          maximum,
          limits,
          slots,
          10000,
          10000,
          [],
          control_work_limit=Some(allowed_work),
        )
      }
    }
    assert_true(
      start(@bounded.control(), workspace - 1, work, 1)
      is Err(@local_sga.MatchEdgesWorkspaceLimit),
    )
    for quantum in [1, 7] {
      for (allowed, maximum) in [(work, 1), (work - 1, 1), (work, 0)] {
        let active = start(@bounded.control(), workspace, allowed, maximum).unwrap()
        let mut terminal = false
        for _ in 0..<20 {
          match @local_sga.advance_match_edges(active, quantum).unwrap() {
            @local_sga.MatchEdgesContinue(..) => ()
            @local_sga.MatchEdgesComplete(output, work=spent, ..) => {
              assert_eq(allowed, work)
              assert_eq(maximum, 1)
              assert_eq(spent, work.to_int64())
              assert_eq(@execution.completed_row_count(output), 1)
              assert_eq(
                @execution.completed_output_row_wire(
                  output, 0, 10000, 10000, 50,
                ).unwrap(),
                expected,
              )
              retained.push(output)
              terminal = true
              break
            }
            @local_sga.MatchEdgesFailed(
              @local_sga.MatchEdgesWorkLimit,
              work=spent,
              ..
            ) => {
              assert_eq(allowed, work - 1)
              assert_eq(spent, allowed.to_int64())
              terminal = true
              break
            }
            @local_sga.MatchEdgesFailed(
              @local_sga.MatchEdgesOutput(@execution.CaptureLimit),
              ..
            ) => {
              assert_eq(maximum, 0)
              terminal = true
              break
            }
            _ =>
              fail(
                "MATCH must preserve the exact limit and never publish a partial result",
              )
          }
        }
        assert_true(terminal)
        assert_true(@local_sga.match_edges_cleanup_pending(active))
        assert_true(@local_sga.cleanup_match_edges(active).unwrap())
        assert_false(@local_sga.cleanup_match_edges(active).unwrap())
        assert_false(@local_sga.match_edges_cleanup_pending(active))
        assert_eq(@local_sga.match_edges_scratch_slots(active), 0)
        assert_true(@graphs.producer_read_available(input))
      }
    }
    // Stop at every quantum-one yield before public completion, including
    // after a private row has been committed but before final publication.
    for prefix in 0..<work {
      let control = @bounded.control()
      let active = start(control, workspace, work, 1).unwrap()
      for _ in 0..<prefix {
        assert_true(
          @local_sga.advance_match_edges(active, 1)
          is Ok(@local_sga.MatchEdgesContinue(..)),
        )
      }
      assert_true(@bounded.request_cancel(control))
      guard @local_sga.advance_match_edges(active, 1)
        is Ok(@local_sga.MatchEdgesStopped(_, work=spent, ..)) else {
        fail("cancelled MATCH must not hand off private output")
      }
      assert_eq(spent, prefix.to_int64())
      assert_true(@local_sga.match_edges_stopped(active))
      assert_true(@local_sga.cleanup_match_edges(active).unwrap())
      assert_false(@local_sga.cleanup_match_edges(active).unwrap())
      assert_false(@local_sga.match_edges_cleanup_pending(active))
      assert_eq(@local_sga.match_edges_scratch_slots(active), 0)
      assert_true(@local_sga.advance_match_edges(active, 1) is Err(_))
      assert_true(@graphs.producer_read_available(input))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
  // Completed Relation rows remain independent of the reclaimed Graph.
  assert_eq(retained.length(), 4)
  for output in retained {
    assert_true(@execution.completed_output_available(output))
    assert_eq(
      @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
      expected,
    )
  }
  for body in ["[{\"select\":[\"key\"]}]", "[{\"filter\":{\"literal\":true}}]"] {
    let consumer = typed_receiver(owner, body, target=@pipeline.Step(0))
    let binding = @execution.bind_completed_input(
      consumer,
      0,
      owner,
      retained[0],
    ).unwrap()
    let result = @execution.execute_generated_sequence(
      task_test_generated(consumer),
      [],
      compute_test_limits(),
      produced=[binding],
    ).unwrap()
    let output = @execution.completed_output(result, @pipeline.Step(0)).unwrap()
    assert_eq(
      @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
      expected,
    )
    assert_true(@execution.completed_output_available(retained[0]))
  }
}

///|
test "keyed MATCH failure and cancellation retain cleanup without partial output" {
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
  let body = "[{\"from\":\"g\",\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"element\"},\"fields\":[\"element\"]}}]"
  let owner = keyed_graph_receiver(graph_owner, body~)
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  for viewed in [false, true] {
    for cancelled in [false, true] {
      let control = @bounded.control()
      let active = if viewed {
        @local_sga.start_match_edges_view(
          control,
          task_test_completion(owner),
          prepared_sequence(owner),
          0,
          @graphs.producer_read_view(input).unwrap(),
          if cancelled {
            10
          } else {
            1
          },
          limits,
          20000,
          10000,
          10000,
          [],
        ).unwrap()
      } else {
        @local_sga.start_match_edges(
          control,
          task_test_completion(owner),
          prepared_sequence(owner),
          0,
          input,
          if cancelled {
            10
          } else {
            1
          },
          limits,
          20000,
          10000,
          10000,
          [],
        ).unwrap()
      }
      assert_true(
        @local_sga.advance_match_edges(active, 1)
        is Ok(@local_sga.MatchEdgesContinue(..)),
      )
      if cancelled {
        assert_true(@bounded.request_cancel(control))
      }
      let mut terminal = false
      for _ in 0..<1000 {
        match @local_sga.advance_match_edges(active, 1).unwrap() {
          @local_sga.MatchEdgesContinue(..) => ()
          @local_sga.MatchEdgesStopped(_, ..) => {
            assert_true(cancelled)
            terminal = true
            break
          }
          @local_sga.MatchEdgesFailed(
            @local_sga.MatchEdgesOutput(@execution.CaptureLimit),
            ..
          ) => {
            assert_false(cancelled)
            terminal = true
            break
          }
          _ => fail("failed keyed match must not publish partial rows")
        }
      }
      assert_true(terminal)
      assert_true(@local_sga.match_edges_cleanup_pending(active))
      assert_true(@local_sga.cleanup_match_edges(active).unwrap())
      assert_false(@local_sga.cleanup_match_edges(active).unwrap())
      assert_false(@local_sga.match_edges_cleanup_pending(active))
      assert_true(@local_sga.advance_match_edges(active, 1) is Err(_))
      assert_true(@graphs.producer_read_available(input))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "keyed MATCH separates heterogeneous definitions and preserves empty typed results" {
  for empty in [false, true] {
    let nodes = keyed_node_source(
      rows=if empty {
        "[]"
      } else {
        "[{\"id\":2,\"tenant\":\"a\",\"name\":\"two\"},{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"}]"
      },
    )
    let edges = keyed_edge_source(rows="[]")
    let body =
      #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["tenant","id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"name","to":"display"}]}},{"name":"IdentityOnly","properties":{"mode":"no_properties"}}]},{"name":"M","from":"nodes","key":["name"],"labels":[{"name":"Other","properties":{"mode":"columns","columns":[{"from":"id","to":"score"}]}}]}],"edges":[]},"as":"g"}]
    let graph_owner = keyed_bridge_owner(nodes, edges, body=Some(body))
    let node_output = carrier_events_source_output(nodes)
    let node_input = @execution.prepare_producer_read(
      graph_owner,
      @execution.bind_completed_input(graph_owner, 0, nodes, node_output).unwrap(),
      1000,
      10000,
    ).unwrap()
    let construction = @local_bridge.start_rows_to_property_graph(
      @bounded.control(),
      prepared_sequence(graph_owner),
      0,
      [node_input, node_input],
      carrier_graph_storage_limits(),
      8192L,
      1000,
      () => true,
    ).unwrap()
    guard keyed_bridge_terminal(construction)
      is @local_bridge.Complete(graph, ..) else {
      fail("constructor failed")
    }
    for
      (definition, label, predicate, numeric) in [
        ("N", "Node", "display = 'one' OR display = 'two'", false),
        ("M", "Other", "score > 0", true),
      ] {
      // Heterogeneous types use different graph-wide property names. The
      // incompatible same-name case is rejected by the admission regressions.
      let property = if numeric { "score" } else { "display" }
      let owner = keyed_graph_receiver(
        graph_owner,
        body="[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"" +
          definition +
          "\",\"label\":\"" +
          label +
          "\",\"bindings\":{\"identity\":\"element\"},\"where\":\"" +
          predicate +
          "\",\"fields\":[\"" +
          property +
          "\",\"element\"]}}]",
      )
      let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
      let active = @local_sga.start_match_nodes_view(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        @graphs.producer_read_view(input).unwrap(),
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
      let output = finish_match_nodes(active).unwrap()
      assert_eq(
        @execution.completed_row_count(output),
        if empty {
          0
        } else {
          2
        },
      )
      let schema = @lower.graph_match_output_schema(
        match @lower.sequence_step(prepared_sequence(owner), 0).unwrap() {
          @lower.GraphMatchStep(prepared) => prepared
          _ => abort("match occurrence")
        },
      )
      let contract = @schema.lookup(schema, @schema.Unqualified(property)).unwrap()
      let value_column = if numeric { 1 } else { 0 }
      assert_eq(
        @execution.completed_column_name(output, value_column),
        Some(property),
      )
      assert_eq(
        @execution.completed_column_name(output, 1 - value_column),
        Some("element"),
      )
      assert_eq(contract.nullable, numeric)
      assert_true(
        if numeric {
          contract.shape is @value_contract.Number
        } else {
          contract.shape is @value_contract.Text(_)
        },
      )
      for row in 0..<(if empty { 0 } else { 2 }) {
        if numeric {
          assert_true(
            @execution.completed_cell(output, row, value_column)
            is Some(Number(value)) &&
            value == (row + 1).to_double(),
          )
        } else {
          assert_true(
            @execution.completed_cell(output, row, value_column)
            is Some(Text(value)) &&
            value == (if row == 0 { "one" } else { "two" }),
          )
        }
      }
      assert_true(@local_sga.cleanup_match_nodes(active).unwrap())
      assert_false(@local_sga.cleanup_match_nodes(active).unwrap())
      assert_true(@execution.completed_output_available(output))
      assert_true(@graphs.producer_read_available(input))
    }
    // The identity-only label does not expose another label's properties.
    assert_true(
      @pipeline.check_with_evidence(
        input_cursor(
          "[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"label\":\"IdentityOnly\",\"where\":\"true\",\"fields\":[\"display\"]}}]",
        ),
        [
          (
            "g",
            @pipeline.ProducedInput(
              @pipeline.produced_input(
                @lower.pipeline(@lower.bound_preparation(graph_owner)),
                @pipeline.Step(0),
              ).unwrap(),
            ),
          ),
        ],
        None,
        Some(input_cursor("\"g\"")),
        {
          max_steps: 10,
          max_work: 100000,
          max_text_bytes: 100000,
          max_nodes: 10000,
          max_tokens: 10000,
          max_depth: 100,
        },
      )
      is Err(_),
    )
    assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
    assert_true(@graphs.discard_completed(graph))
  }
}

///|
fn keyed_path_owner(
  graph_owner : @lower.BoundPrepared,
  mode : String,
  label? : String = "r",
  start_domain? : String? = None,
) -> (@lower.BoundPrepared, String) {
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(graph)) else {
    abort("keyed Graph schema missing")
  }
  let domain = @carrier_contract.property_graph_domain(
    @carrier_contract.graph_property_definition(graph),
  )
  // Independently authored semantic identity, not copied from runtime output.
  let start = "{\"definition\":\"N\",\"domain\":\"" +
    start_domain.unwrap_or(domain) +
    "\",\"key\":[\"a\",1],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}"
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
      start +
      "]},\"path_mode\":\"" +
      mode +
      "\",\"hops\":[{\"direction\":\"out\",\"edge_types\":[\"" +
      label +
      "\"]},{\"direction\":\"out\",\"edge_types\":[\"" +
      label +
      "\"]}],\"emit\":\"paths\"}}]",
    ),
    [
      (
        "g",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(graph_owner)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"g\"")),
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
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
  (owner, domain)
}

///|
test "keyed paths preserve parallel self-loops under WALK TRAIL and ACYCLIC" {
  let nodes = keyed_node_source()
  // Opposite to canonical identity order: input positions must not decide
  // output order or conceal an endpoint-only edge comparator.
  let edges = keyed_edge_source(
    rows="[{\"key\":11,\"tenant\":\"a\",\"src\":1,\"dst\":1},{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":1}]",
  )
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("constructor failed")
  }
  for
    (mode, expected) in [
      ("walk", [(10, 10), (10, 11), (11, 10), (11, 11)]),
      ("trail", [(10, 11), (11, 10)]),
      ("acyclic", []),
    ] {
    for (quantum, viewed) in [(1, false), (7, false), (1, true), (7, true)] {
      let (owner, domain) = keyed_path_owner(graph_owner, mode)
      let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
      let active_result = if viewed {
        @local_sga.start_traverse_view(
          @bounded.control(),
          task_test_completion(owner),
          prepared_sequence(owner),
          0,
          @graphs.producer_read_view(input).unwrap(),
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
        )
      } else {
        @local_sga.start_traverse(
          @bounded.control(),
          task_test_completion(owner),
          prepared_sequence(owner),
          0,
          input,
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
        )
      }
      assert_true(active_result is Ok(_))
      let active = active_result.unwrap()
      let mut output = None
      for _ in 0..<100000 {
        match @local_sga.advance_traverse(active, quantum).unwrap() {
          @local_sga.TraverseContinue(..) => ()
          @local_sga.TraverseComplete(rows, ..) => {
            output = Some(rows)
            break
          }
          @local_sga.TraverseFailed(_, ..) =>
            fail("keyed path traversal failed")
          _ => fail("keyed path traversal must finish")
        }
      }
      let output = output.unwrap()
      assert_eq(@execution.completed_row_count(output), expected.length())
      let node = "{\"definition\":\"N\",\"domain\":\"" +
        domain +
        "\",\"key\":[\"a\",1],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}"
      let edge = fn(key : Int) {
        "{\"definition\":\"E\",\"domain\":\"" +
        domain +
        "\",\"key\":[" +
        key.to_string() +
        "],\"key_types\":[{\"kind\":\"number\"}]}"
      }
      for row, (first, second) in expected {
        let independent = "{\"edge_ids\":[" +
          edge(first) +
          "," +
          edge(second) +
          "],\"end_id\":" +
          node +
          ",\"hop_count\":2,\"node_ids\":[" +
          node +
          "," +
          node +
          "," +
          node +
          "],\"start_id\":" +
          node +
          "}"
        assert_eq(
          @execution.completed_output_row_wire(output, row, 10000, 10000, 50).unwrap(),
          independent,
        )
      }
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.traverse_cleanup_pending(active))
      assert_false(@local_sga.cleanup_traverse(active).unwrap())
      assert_true(@execution.completed_output_available(output))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "keyed paths reject cross-domain starts without changing retained material" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("constructor failed")
  }
  let (owner, _) = keyed_path_owner(
    graph_owner,
    "walk",
    start_domain=Some(
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    ),
  )
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  for viewed in [false, true] {
    let active = if viewed {
      @local_sga.start_traverse_view(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        @graphs.producer_read_view(input).unwrap(),
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
    } else {
      @local_sga.start_traverse(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        input,
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
    }
    assert_true(
      finish_traverse(active)
      is Err(
        @local_sga.TraversePathIssue(@local_sga.TraversePathsInputUnavailable)
      ),
    )
    assert_true(@local_sga.cleanup_traverse(active).unwrap())
    assert_false(@local_sga.cleanup_traverse(active).unwrap())
    assert_true(@graphs.producer_read_available(input))
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "keyed paths filter static labels and fail privately under capacity or cancellation" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("constructor failed")
  }
  for (label, expected) in [("R", 4), ("r", 4), ("key", 0)] {
    let (owner, _) = keyed_path_owner(graph_owner, "walk", label~)
    let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
    let active = @local_sga.start_traverse(
      @bounded.control(),
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      input,
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
    let output = finish_traverse(active).unwrap()
    assert_eq(@execution.completed_row_count(output), expected)
    assert_true(@local_sga.cleanup_traverse(active).unwrap())
    assert_false(@local_sga.cleanup_traverse(active).unwrap())
    assert_true(@graphs.producer_read_available(input))
  }
  let (owner, _) = keyed_path_owner(graph_owner, "walk")
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  for (max_rows, cancelled) in [(3, false), (10, true)] {
    let control = @bounded.control()
    let active = @local_sga.start_traverse(
      control,
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      input,
      max_rows,
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
    assert_true(
      @local_sga.advance_traverse(active, 1).unwrap()
      is @local_sga.TraverseContinue(..),
    )
    if cancelled {
      assert_true(@bounded.request_cancel(control))
    }
    let mut terminal = false
    for _ in 0..<100000 {
      match @local_sga.advance_traverse(active, 1).unwrap() {
        @local_sga.TraverseContinue(..) => ()
        @local_sga.TraverseFailed(issue, ..) => {
          assert_false(cancelled)
          assert_eq(
            issue,
            @local_sga.TraversePathIssue(@local_sga.TraversePathsOutputLimit),
          )
          terminal = true
          break
        }
        @local_sga.TraverseStopped(_, ..) => {
          assert_true(cancelled)
          terminal = true
          break
        }
        @local_sga.TraverseComplete(_, ..) =>
          fail("capacity/cancel exposed partial path rows")
      }
    }
    assert_true(terminal)
    assert_true(@local_sga.traverse_stopped(active))
    assert_true(@local_sga.traverse_cleanup_pending(active))
    assert_true(@local_sga.cleanup_traverse(active).unwrap())
    assert_false(@local_sga.traverse_cleanup_pending(active))
    assert_false(@local_sga.cleanup_traverse(active).unwrap())
    assert_true(@local_sga.advance_traverse(active, 1) is Err(_))
    assert_true(@graphs.producer_read_available(input))
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "existing selected Graph provider executes keyed TRAIL from one exact Carrier input" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("constructor failed")
  }
  let (owner, _) = keyed_path_owner(graph_owner, "trail")
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let provider = @local_sga_provider.provider(
    // A path row contains seven complete scoped identities, not seven scalar
    // legacy IDs. Its independently authored expected schema needs this bound.
    {
      ..carrier_graph_storage_limits(),
      max_value_nodes: 1000,
      max_work: 10000,
    },
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let view = @graphs.producer_read_view(input).unwrap()
  let run = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    [@local_connector.managed_provider_carrier_input(view)],
    10,
    10000,
  ).unwrap()
  let mut output = None
  for _ in 0..<100000 {
    match @local_connector.advance_managed_provider(run, 1).unwrap() {
      @local_connector.Continue(..) => ()
      @local_connector.Complete(rows, ..) => {
        output = Some(rows)
        break
      }
      _ => fail("selected keyed TRAIL provider failed")
    }
  }
  assert_eq(@execution.completed_row_count(output.unwrap()), 2)
  assert_true(@local_connector.cleanup_managed_provider(run).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(run).unwrap())
  assert_true(@execution.completed_output_available(output.unwrap()))
  assert_true(@graphs.producer_read_available(input))
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "snapshot policy is installed and charged before constructor input access" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let owner = keyed_bridge_owner(nodes, edges)
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let base = @execution.generated_sequence_capacity(
    generated,
    dispatch_test_limits().local_execution,
    dispatch_test_limits().guards,
  ).unwrap()
  let policy : @local_sga_provider.SnapshotPolicy = {
    serialization: snapshot_caps(),
    read: {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
    maximum_bytes: 100000,
    maximum_frame_bytes: 100000,
    workspace_bytes: 1000000L,
  }
  let memory = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    base,
  )
  let persistent = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    base,
    snapshot_policy=Some(policy),
  )
  let before = @local_connector.managed_provider_capacity(memory, generated).unwrap()
  let after = @local_connector.managed_provider_capacity(persistent, generated).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(after),
    @execution.execution_capacity_execution_bytes(before) + 1000000L,
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(after),
    @execution.execution_capacity_retained_bytes(before),
  )
  let invalid = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    base,
    snapshot_policy=Some({ ..policy, maximum_frame_bytes: 100001, }),
  )
  assert_true(
    @local_connector.managed_provider_capacity(invalid, generated) is None,
  )
  assert_true(
    @local_connector.start_managed_provider_with_inputs(
      invalid,
      generated,
      [],
      10,
      1000,
    )
    is Err(_),
  )
  let active = @local_connector.start_managed_provider_with_inputs(
    persistent,
    generated,
    keyed_bridge_inputs(owner, nodes, edges).map(
      @local_connector.managed_provider_relation_input,
    ),
    10,
    1000,
  ).unwrap()
  let mut material = None
  for _ in 0..<1000 {
    match @local_connector.advance_managed_provider(active, 1).unwrap() {
      @local_connector.Continue(..) => ()
      @local_connector.CarrierComplete(value, ..) => {
        material = Some(value)
        break
      }
      _ => fail("installed snapshot policy prevented constructor completion")
    }
  }
  let material = material.unwrap()
  let snapshot = @carrier_runtime.material_prepare_snapshot(material)
    .unwrap()
    .unwrap()
  assert_eq(snapshot.workspace_bytes, 1000000L)
  assert_eq(snapshot.maximum_bytes, 100000)
  assert_eq(snapshot.maximum_frame_bytes, 100000)
  assert_true(
    @carrier_runtime.material_prepare_snapshot(material)
    is Err(@carrier_runtime.SnapshotAlreadyClaimed),
  )
  // The operation may already dispose its source. Completion is the same
  // Material's custody status, not whether this request changed that source.
  @carrier_runtime.reclaim_material(material) |> ignore
  assert_false(@carrier_runtime.material_cleanup_pending(material))
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
}

///|
test "existing Graph provider retains keyed constructor material and cleanup custody" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let owner = keyed_bridge_owner(nodes, edges)
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  let run = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    keyed_bridge_inputs(owner, nodes, edges).map(
      @local_connector.managed_provider_relation_input,
    ),
    10,
    1000,
  ).unwrap()
  let mut material = None
  for _ in 0..<1000 {
    match @local_connector.advance_managed_provider(run, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(output, ..) => {
        material = Some(output)
        break
      }
      _ => fail("keyed constructor provider must complete as a Graph")
    }
  }
  let material = material.unwrap()
  assert_eq(
    @carrier_runtime.material_kind(material),
    @carrier_contract.GraphKind,
  )
  assert_true(@carrier_runtime.material_available(material))
  assert_true(
    @carrier_runtime.completion_reference_matches_port(
      @carrier_runtime.material_reference(material),
      owner,
      @pipeline.Step(0),
    ),
  )
  let view = @carrier_runtime.material_prepare_view(
    material,
    keyed_graph_receiver(owner),
    0,
    owner,
  ).unwrap()
  assert_eq(@carrier_runtime.producer_view_node_count(view), Some(1))
  assert_eq(@carrier_runtime.producer_view_edge_count(view), Some(2))
  assert_true(
    @carrier_runtime.producer_view_node_key(view, 0, 0).unwrap().value
    is @admitted.Text("a"),
  )
  assert_true(
    @carrier_runtime.producer_view_node_key(view, 0, 1).unwrap().value
    is @admitted.Number(1.0),
  )
  assert_true(
    @carrier_runtime.producer_view_edge_key(view, 0, 0).unwrap().value
    is @admitted.Number(10.0),
  )
  assert_true(
    @carrier_runtime.producer_view_edge_key(view, 1, 0).unwrap().value
    is @admitted.Number(11.0),
  )
  assert_true(
    @carrier_runtime.producer_view_node_key(view, 0, 2)
    is Err(@carrier_runtime.InvalidField),
  )
  assert_true(
    @carrier_runtime.producer_view_edge_key(view, 2, 0)
    is Err(@carrier_runtime.InvalidRecord),
  )
  let first = @carrier_runtime.producer_view_edge_identity(view, 0).unwrap()
  let second = @carrier_runtime.producer_view_edge_identity(view, 1).unwrap()
  assert_eq(
    @carrier_runtime.producer_view_edge_identity_index(view, first),
    Ok(Some(0)),
  )
  assert_eq(
    @carrier_runtime.producer_view_edge_identity_index(view, second),
    Ok(Some(1)),
  )
  assert_eq(@carrier_runtime.producer_view_edge_endpoints(view, 0), Ok((0, 0)))
  assert_eq(@carrier_runtime.producer_view_edge_endpoints(view, 1), Ok((0, 0)))
  assert_true(
    @carrier_runtime.producer_view_node_property(view, 0, 0).unwrap().value
    is @admitted.Text("one"),
  )
  // Provider cleanup relinquishes its session, not the delivered material.
  assert_true(@local_connector.cleanup_managed_provider(run).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(run).unwrap())
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
  assert_false(@carrier_runtime.material_available(material))
  assert_eq(@carrier_runtime.producer_view_node_count(view), None)
  assert_true(
    @carrier_runtime.producer_view_edge_key(view, 0, 0)
    is Err(@carrier_runtime.Unavailable),
  )
}

///|
test "keyed constructor provider refuses surplus inputs and never completes partial Graphs" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let owner = keyed_bridge_owner(nodes, edges)
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let inputs = keyed_bridge_inputs(owner, nodes, edges)
  let supplied = inputs.map(@local_connector.managed_provider_relation_input)
  for cancelled in [false, true] {
    let limits = if cancelled {
      carrier_graph_storage_limits()
    } else {
      { ..carrier_graph_storage_limits(), max_edges: 1, }
    }
    let provider = @local_sga_provider.provider(
      limits,
      4096L,
      @execution.generated_sequence_capacity(
        generated,
        dispatch_test_limits().local_execution,
        dispatch_test_limits().guards,
      ).unwrap(),
    )
    let surplus = supplied.copy()
    surplus.push(supplied[0])
    assert_true(
      @local_connector.start_managed_provider_with_inputs(
        provider, generated, surplus, 10, 1000,
      )
      is Err(_),
    )
    let run = @local_connector.start_managed_provider_with_inputs(
      provider, generated, supplied, 10, 1000,
    ).unwrap()
    assert_true(
      @local_connector.advance_managed_provider(run, 1).unwrap()
      is @local_connector.Continue(..),
    )
    if cancelled {
      assert_true(@local_connector.cancel_managed_provider(run))
    }
    let mut terminated = false
    for _ in 0..<1000 {
      match @local_connector.advance_managed_provider(run, 1).unwrap() {
        @local_connector.Continue(..) => ()
        @local_connector.Stopped(..) if cancelled => {
          terminated = true
          break
        }
        @local_connector.Failed(_, ..) if !cancelled => {
          terminated = true
          break
        }
        _ =>
          fail(
            "failure or cancellation must not publish partial Graph material",
          )
      }
    }
    assert_true(terminated)
    assert_true(@local_connector.cleanup_managed_provider(run).unwrap())
    assert_true(@local_connector.cleanup_managed_provider(run).unwrap())
    assert_true(@local_connector.advance_managed_provider(run, 1) is Err(_))
    for input in inputs {
      assert_true(@execution.producer_read_available(input))
    }
  }
}

///|
test "keyed constructor lowering and bounded execution retain composite nodes and parallel edges" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let owner = keyed_bridge_owner(nodes, edges)
  let sequence = prepared_sequence(owner)
  guard @lower.sequence_step(sequence, 0)
    is Some(@lower.PropertyGraphConstructionStep(prepared)) else {
    fail("new profile must not borrow the tuple constructor")
  }
  let binding = @lower.property_graph_construction_node_at(prepared, 0).unwrap()
  // Input fields are sorted by the common schema owner: id, name, tenant.
  assert_eq(@lower.property_binding_keys(binding), [2, 0])
  assert_eq(@lower.property_binding_properties(binding), [1])
  let leaked = @lower.property_binding_keys(binding)
  leaked[0] = 99
  assert_eq(@lower.property_binding_keys(binding), [2, 0])
  let writer = @encode.writer(100000, 10000, 100)
  @lower.emit_sequence_steps(sequence, writer)
  let emitted = @encode.finish(writer)
  assert_true(emitted.contains("\"op\":\"BRIDGE.rows.to_property_graph\""))
  assert_true(
    emitted.contains("\"version\":\"actql-property-graph-contract/0.1\""),
  )
  assert_false(emitted.contains("\"op\":\"REL.join\""))
  let inputs = keyed_bridge_inputs(owner, nodes, edges)
  let active = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    sequence,
    0,
    inputs,
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(active) is @local_bridge.Complete(completed, ..) else {
    fail("checked composite constructor must complete")
  }
  let storage = @graphs.completed_storage(completed).unwrap()
  // Two NULL-key rows and one dangling edge are excluded, not normalized into
  // another identity. The two self-loops keep their independently declared keys.
  assert_eq(@graph_storage.node_count(storage), 1)
  assert_eq(@graph_storage.edge_count(storage), 2)
  assert_eq(@graph_storage.edge_endpoints(storage, 0), Some((0, 0)))
  assert_eq(@graph_storage.edge_endpoints(storage, 1), Some((0, 0)))
  let first = @graph_storage.edge_identity(storage, 0).unwrap()
  let second = @graph_storage.edge_identity(storage, 1).unwrap()
  assert_eq(@graph_storage.edge_identity_index(storage, first), Ok(Some(0)))
  assert_eq(@graph_storage.edge_identity_index(storage, second), Ok(Some(1)))
  let key = @graph_storage.node_typed_key(storage, 0).unwrap()
  assert_true(key[0].value is @admitted.Text("a"))
  assert_true(key[1].value is @admitted.Number(1.0))
  assert_true(
    @graph_storage.node_property(storage, 0, 0).unwrap().value
    is @admitted.Text("one"),
  )
  assert_eq(
    @graphs.evidence_input_rows(@graphs.completed_evidence(completed).unwrap()),
    6,
  )
  assert_true(@local_bridge.cleanup_rows_to_graph(active).unwrap())
  assert_true(@graphs.discard_completed(completed))
  assert_false(@graphs.completed_available(completed))
}

///|
test "keyed constructor rejects duplicate edge keys before missing endpoint exclusion" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source(
    rows="[{\"key\":12,\"tenant\":\"a\",\"src\":1,\"dst\":9},{\"key\":12,\"tenant\":\"a\",\"src\":1,\"dst\":9}]",
  )
  let owner = keyed_bridge_owner(nodes, edges)
  let active = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    keyed_bridge_inputs(owner, nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  assert_true(
    keyed_bridge_terminal(active)
    is @local_bridge.Failed(@local_bridge.InvalidGraphRecord(1), ..),
  )
  assert_true(@local_bridge.cleanup_rows_to_graph(active).unwrap())
  assert_false(@local_bridge.rows_to_graph_cleanup_pending(active))
  assert_true(@local_bridge.advance_rows_to_graph(active, 1) is Err(_))
}

///|
test "keyed constructor capacity failure and cancellation never hand off partial material" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let owner = keyed_bridge_owner(nodes, edges)
  let sequence = prepared_sequence(owner)
  let inputs = keyed_bridge_inputs(owner, nodes, edges)
  let limits = { ..carrier_graph_storage_limits(), max_edges: 1, }
  let exhausted = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    sequence,
    0,
    inputs,
    limits,
    4096L,
    1000,
    () => true,
  ).unwrap()
  assert_true(keyed_bridge_terminal(exhausted) is @local_bridge.Failed(_, ..))
  assert_true(@local_bridge.cleanup_rows_to_graph(exhausted).unwrap())
  assert_false(@local_bridge.rows_to_graph_cleanup_pending(exhausted))
  let control = @bounded.control()
  let cancelled = @local_bridge.start_rows_to_property_graph(
    control,
    sequence,
    0,
    inputs,
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  assert_true(
    @local_bridge.advance_rows_to_graph(cancelled, 5)
    is Ok(@local_bridge.Continue(..)),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(keyed_bridge_terminal(cancelled) is @local_bridge.Stopped(_, ..))
  assert_true(@local_bridge.cleanup_rows_to_graph(cancelled).unwrap())
  assert_false(@local_bridge.rows_to_graph_cleanup_pending(cancelled))
  assert_true(@local_bridge.advance_rows_to_graph(cancelled, 1) is Err(_))
}

///|
test "common constructor keeps empty keyed definition schemas" {
  let nodes = keyed_node_source(rows="[]")
  let edges = keyed_edge_source(rows="[]")
  let owner = keyed_bridge_owner(nodes, edges)
  let sequence = prepared_sequence(owner)
  let inputs = keyed_bridge_inputs(owner, nodes, edges)
  let active = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    inputs,
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(active) is @local_bridge.Complete(completed, ..) else {
    fail("empty input still has an admitted graph schema")
  }
  let storage = @graphs.completed_storage(completed).unwrap()
  assert_eq(@graph_storage.node_count(storage), 0)
  assert_eq(@graph_storage.edge_count(storage), 0)
  guard @graph_storage.carrier(storage) is @carrier_contract.GraphValue(graph) else {
    fail("Graph carrier")
  }
  let definition = @carrier_contract.graph_property_definition(graph)
  assert_eq(
    @carrier_contract.property_graph_node_definitions(definition).length(),
    1,
  )
  assert_eq(
    @carrier_contract.property_graph_edge_definitions(definition).length(),
    1,
  )
  let node = @carrier_contract.property_graph_node_at(definition, 0).unwrap()
  assert_eq(@carrier_contract.property_definition_labels(node), ["Node"])
  assert_eq(
    @carrier_contract.field_count(
      @carrier_contract.property_definition_properties(node),
    ),
    1,
  )
  assert_true(@local_bridge.cleanup_rows_to_graph(active).unwrap())
  assert_true(@graphs.discard_completed(completed))
}

///|
test "keyed constructor rejects foreign input custody and bounds preparation and control work" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let owner = keyed_bridge_owner(nodes, edges)
  let sequence = prepared_sequence(owner)
  let inputs = keyed_bridge_inputs(owner, nodes, edges)
  let foreign = keyed_bridge_owner(nodes, edges)
  assert_true(
    @local_bridge.start_rows_to_property_graph(
      @bounded.control(),
      prepared_sequence(foreign),
      0,
      inputs,
      carrier_graph_storage_limits(),
      4096L,
      1000,
      () => true,
    )
    is Err(@local_bridge.InvalidGraphKernel),
  )
  assert_true(
    @local_bridge.start_rows_to_property_graph(
      @bounded.control(),
      sequence,
      0,
      inputs,
      carrier_graph_storage_limits(),
      4096L,
      16,
      () => true,
    )
    is Err(@local_bridge.GraphWorkspaceLimit),
  )
  let active = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    sequence,
    0,
    inputs,
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
    control_work_limit=Some(8),
  ).unwrap()
  assert_true(
    keyed_bridge_terminal(active)
    is @local_bridge.Failed(@local_bridge.GraphControlWorkLimit, ..),
  )
  assert_true(@local_bridge.cleanup_rows_to_graph(active).unwrap())
  assert_false(@local_bridge.rows_to_graph_cleanup_pending(active))
  // The schema codec uses this same preparation depth budget. A separate
  // hard-coded allowance must not let constructor metadata bypass it.
  assert_true(
    @lower.prepare_sequence(owner, {
      max_steps: 100,
      max_rows: 100,
      max_cells: 10000,
      max_bindings: 100,
      max_name_bytes: 10000,
      expressions: {
        max_nodes: 10000,
        max_work: 100000,
        max_depth: 0,
        max_literal_nodes: 10000,
        max_literal_text_bytes: 10000,
      },
    })
    is Err(@lower.GraphConstructionFailure(0, _)),
  )
}

///|
test "keyed constructor admits exact control work and workspace and refuses one short" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let owner = keyed_bridge_owner(nodes, edges)
  let sequence = prepared_sequence(owner)
  let inputs = keyed_bridge_inputs(owner, nodes, edges)
  // Independent fixture accounting: 16 fixed slots, 2 input handles,
  // node binding (3 columns + 7 metadata), edge binding (5 + 7),
  // and 5 maximum live row slots = 45. The separate storage ceiling stays
  // unchanged; this is not a claim that identity/value storage costs zero.
  let workspace = 16 + 2 + (3 + 7) + (5 + 7) + 5
  // Two node rows cost Begin + three cells + Commit each; four edge
  // rows cost Begin + five cells + Commit each. Two exhausted bindings,
  // final Begin, three input-verification polls and Finish add seven.
  let work = 2 * (1 + 3 + 1) + 4 * (1 + 5 + 1) + 7
  assert_eq(workspace, 45)
  assert_eq(work, 45)
  assert_true(
    @local_bridge.start_rows_to_property_graph(
      @bounded.control(),
      sequence,
      0,
      inputs,
      carrier_graph_storage_limits(),
      4096L,
      workspace - 1,
      () => true,
    )
    is Err(@local_bridge.GraphWorkspaceLimit),
  )
  for quantum in [1, 7] {
    for allowed in [work - 1, work] {
      let active = @local_bridge.start_rows_to_property_graph(
        @bounded.control(),
        sequence,
        0,
        inputs,
        carrier_graph_storage_limits(),
        4096L,
        workspace,
        () => true,
        control_work_limit=Some(allowed),
      ).unwrap()
      let mut observed_work = 0L
      let mut terminal = false
      for _ in 0..<100 {
        match @local_bridge.advance_rows_to_graph(active, quantum).unwrap() {
          // The bounded session reports its cumulative value, not a delta.
          @local_bridge.Continue(work~, ..) => {
            assert_true(work >= observed_work)
            observed_work = work
          }
          @local_bridge.Complete(output, work~, ..) => {
            assert_true(work >= observed_work)
            observed_work = work
            assert_eq(allowed, 45)
            let storage = @graphs.completed_storage(output).unwrap()
            assert_eq(@graph_storage.node_count(storage), 1)
            assert_eq(@graph_storage.edge_count(storage), 2)
            assert_true(@graphs.discard_completed(output))
            terminal = true
            break
          }
          @local_bridge.Failed(@local_bridge.GraphControlWorkLimit, work~, ..) => {
            assert_true(work >= observed_work)
            observed_work = work
            assert_eq(allowed, 44)
            terminal = true
            break
          }
          _ => fail("exact independently calculated boundary")
        }
      }
      assert_true(terminal)
      assert_eq(observed_work, allowed.to_int64())
      assert_true(@local_bridge.cleanup_rows_to_graph(active).unwrap())
      assert_false(@local_bridge.rows_to_graph_cleanup_pending(active))
      assert_false(@local_bridge.cleanup_rows_to_graph(active).unwrap())
      assert_true(@local_bridge.advance_rows_to_graph(active, 1) is Err(_))
    }
  }
}

///|
test "keyed constructor rejects identical duplicate nodes" {
  let nodes = keyed_node_source(
    rows="[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"},{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"}]",
  )
  let edges = keyed_edge_source(rows="[]")
  let owner = keyed_bridge_owner(nodes, edges)
  let active = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    keyed_bridge_inputs(owner, nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  assert_true(
    keyed_bridge_terminal(active)
    is @local_bridge.Failed(@local_bridge.InvalidGraphRecord(1), ..),
  )
  assert_true(@local_bridge.cleanup_rows_to_graph(active).unwrap())
  assert_false(@local_bridge.rows_to_graph_cleanup_pending(active))
}

///|
test "keyed constructor retains definition order and repeated uses of one producer" {
  let source = keyed_node_source()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      (
        #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"Z","from":"nodes","key":["tenant","id"]},{"name":"A","from":"nodes","key":["tenant","id"]}],"edges":[]},"as":"g"}]
      ),
    ),
    [
      (
        "nodes",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
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
  let owner = @lower.bind_parameters(
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
  let output = carrier_events_source_output(source)
  let input = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source, output).unwrap(),
    1000,
    10000,
  ).unwrap()
  let active = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    [input, input],
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(active) is @local_bridge.Complete(completed, ..) else {
    fail("each definition must retain its own producer occurrence")
  }
  let storage = @graphs.completed_storage(completed).unwrap()
  assert_eq(@graph_storage.node_count(storage), 2)
  assert_eq(@graph_storage.node_definition_index(storage, 0), Some(0))
  assert_eq(@graph_storage.node_definition_index(storage, 1), Some(1))
  let first = @graph_storage.node_identity(storage, 0).unwrap()
  let second = @graph_storage.node_identity(storage, 1).unwrap()
  assert_eq(@graph_storage.node_index(storage, first), Ok(Some(0)))
  assert_eq(@graph_storage.node_index(storage, second), Ok(Some(1)))
  assert_eq(
    @graphs.evidence_input_rows(@graphs.completed_evidence(completed).unwrap()),
    4,
  )
  assert_true(@local_bridge.cleanup_rows_to_graph(active).unwrap())
  assert_true(@graphs.discard_completed(completed))
}
