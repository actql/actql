///|
fn subgraph_checked_wire(value : @admitted.CheckedValue) -> String raise {
  let writer = @encode.writer(10000, 1000, 100)
  @admitted.emit_checked_wire_value(value, writer)
  @encode.finish(writer)
}

///|
fn keyed_subgraph_relation_owner(
  graph : @lower.BoundPrepared,
  selector : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"from\":\"selected\",\"id\":\"key\"},\"edges\":\"true\"}}]",
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
        "selected",
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
test "keyed subgraph false edge admits exact work and workspace" {
  let nodes = keyed_node_source(
    rows="[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"}]",
  )
  let edges = keyed_edge_source(
    rows="[{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":1}]",
  )
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
    fail("source Graph construction")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(contract)) else {
    fail("source Graph contract")
  }
  let domain = @carrier_contract.graph_domain(
    @carrier_contract.graph_definition(contract),
  )
  let profile = @carrier_contract.graph_definition(contract)
  assert_eq(@carrier_contract.graph_node_count(profile), 1)
  assert_eq(@carrier_contract.graph_edge_count(profile), 1)
  let node_definition = @carrier_contract.graph_node_at(profile, 0).unwrap()
  assert_eq(
    @carrier_contract.graph_element_definition_key_count(node_definition),
    2,
  )
  assert_eq(
    @carrier_contract.field_count(
      @carrier_contract.graph_element_definition_properties(node_definition),
    ),
    1,
  )
  let owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"ids\":[{\"definition\":\"N\",\"domain\":\"" +
      domain +
      "\",\"key\":[\"a\",1],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}]},\"edges\":\"false\"}}]",
  )
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  // Two profile phases consume two steps each. Output preparation consumes one,
  // selection initialization and resolution two each, node visitation two,
  // two key reads, one property read, node commit one, rejected edge and end
  // marker two, and finish one: 18 total. Phase transitions do not read data.
  for stored in [false, true] {
    for limit in [17, 18] {
      let limits = { ..carrier_graph_storage_limits(), max_work: 1000, }
      let started = if stored {
        @local_sga.start_subgraph(
          @bounded.control(),
          prepared_sequence(owner),
          0,
          input,
          None,
          limits,
          8192L,
          () => true,
          control_work_limit=Some(limit),
        )
      } else {
        @local_sga.start_subgraph_view(
          @bounded.control(),
          prepared_sequence(owner),
          0,
          @graphs.producer_read_view(input).unwrap(),
          None,
          limits,
          8192L,
          () => true,
          control_work_limit=Some(limit),
        )
      }
      let active = started.unwrap()
      let mut terminal = false
      for _ in 0..<30 {
        match @local_sga.advance_subgraph(active, 1).unwrap() {
          @local_sga.SubgraphContinue(..) => ()
          @local_sga.SubgraphComplete(result, ..) => {
            assert_eq(limit, 18)
            assert_eq(
              @graph_storage.node_count(
                @graphs.completed_storage(result).unwrap(),
              ),
              1,
            )
            assert_eq(
              @graph_storage.edge_count(
                @graphs.completed_storage(result).unwrap(),
              ),
              0,
            )
            assert_true(@graphs.discard_completed(result))
            terminal = true
            break
          }
          @local_sga.SubgraphFailed(@local_sga.SubgraphWorkLimit, ..) => {
            assert_eq(limit, 17)
            terminal = true
            break
          }
          _ => fail("unexpected subgraph boundary result")
        }
      }
      assert_true(terminal)
      assert_true(@local_sga.cleanup_subgraph(active).unwrap())
    }
  }
  // The edge definition needs five scratch slots. The selector bitmap needs
  // one, the fixed scratch reservation adds sixteen, and one retained node
  // uses eight storage slots (record, indices, key and property values).
  for stored in [false, true] {
    for workspace in [29, 30] {
      let limits = {
        ..carrier_graph_storage_limits(),
        max_work: 1000,
        max_workspace_slots: workspace,
      }
      let started = if stored {
        @local_sga.start_subgraph(
          @bounded.control(),
          prepared_sequence(owner),
          0,
          input,
          None,
          limits,
          8192L,
          () => true,
          control_work_limit=Some(18),
        )
      } else {
        @local_sga.start_subgraph_view(
          @bounded.control(),
          prepared_sequence(owner),
          0,
          @graphs.producer_read_view(input).unwrap(),
          None,
          limits,
          8192L,
          () => true,
          control_work_limit=Some(18),
        )
      }
      let active = started.unwrap()
      let mut terminal = false
      for _ in 0..<30 {
        match @local_sga.advance_subgraph(active, 1).unwrap() {
          @local_sga.SubgraphContinue(..) => ()
          @local_sga.SubgraphComplete(result, ..) => {
            assert_eq(workspace, 30)
            assert_true(@graphs.discard_completed(result))
            terminal = true
            break
          }
          @local_sga.SubgraphFailed(
            @local_sga.SubgraphOutput(
              @graphs.Storage(@graph_storage.WorkspaceLimit)
            ),
            ..
          ) => {
            assert_eq(workspace, 29)
            terminal = true
            break
          }
          _ => fail("unexpected subgraph workspace result")
        }
      }
      assert_true(terminal)
      assert_true(@local_sga.cleanup_subgraph(active).unwrap())
    }
  }
  for stored in [false, true] {
    let control = @bounded.control()
    let limits = { ..carrier_graph_storage_limits(), max_work: 1000, }
    let started = if stored {
      @local_sga.start_subgraph(
        control,
        prepared_sequence(owner),
        0,
        input,
        None,
        limits,
        8192L,
        () => true,
        control_work_limit=Some(18),
      )
    } else {
      @local_sga.start_subgraph_view(
        control,
        prepared_sequence(owner),
        0,
        @graphs.producer_read_view(input).unwrap(),
        None,
        limits,
        8192L,
        () => true,
        control_work_limit=Some(18),
      )
    }
    let active = started.unwrap()
    let mut progressed = false
    for _ in 0..<20 {
      match @local_sga.advance_subgraph(active, 1).unwrap() {
        @local_sga.SubgraphContinue(progress~, ..) =>
          if progress > 0L {
            progressed = true
            break
          }
        _ => fail("subgraph terminated before cancellation")
      }
    }
    assert_true(progressed)
    assert_true(@bounded.request_cancel(control))
    assert_true(
      @local_sga.advance_subgraph(active, 1)
      is Ok(@local_sga.SubgraphStopped(_, ..)),
    )
    assert_true(@local_sga.cleanup_subgraph(active).unwrap())
    assert_true(@graphs.producer_read_available(input))
  }
  assert_true(@graphs.producer_read_available(input))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "bounded keyed subgraph preserves independent edges and source Graph" {
  let nodes = keyed_node_source(
    rows="[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"},{\"id\":2,\"tenant\":\"a\",\"name\":\"two\"},{\"id\":3,\"tenant\":\"a\",\"name\":\"three\"}]",
  )
  let edges = keyed_edge_source(
    rows="[{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":2},{\"key\":11,\"tenant\":\"a\",\"src\":1,\"dst\":2},{\"key\":12,\"tenant\":\"a\",\"src\":2,\"dst\":3}]",
  )
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
    fail("source Graph construction")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(contract)) else {
    fail("source Graph contract")
  }
  let domain = @carrier_contract.graph_domain(
    @carrier_contract.graph_definition(contract),
  )
  let identity = fn(key : Int) {
    "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[\"a\"," +
    key.to_string() +
    "],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}"
  }
  let owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"ids\":[" +
      identity(1) +
      "," +
      identity(2) +
      "]}}}]",
  )
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let control = @bounded.control()
  let active = @local_sga.start_subgraph_view(
    control,
    prepared_sequence(owner),
    0,
    @graphs.producer_read_view(input).unwrap(),
    None,
    { ..carrier_graph_storage_limits(), max_work: 10000, },
    8192L,
    () => true,
  ).unwrap()
  let mut result = None
  for _ in 0..<1000 {
    match @local_sga.advance_subgraph(active, 1).unwrap() {
      @local_sga.SubgraphContinue(work~, ..) => assert_true(work > 0L)
      @local_sga.SubgraphComplete(output, ..) => {
        result = Some(output)
        break
      }
      @local_sga.SubgraphFailed(_, ..) => fail("subgraph failed")
      @local_sga.SubgraphStopped(_, ..) => fail("subgraph stopped")
    }
  }
  let result = result.unwrap()
  let storage = @graphs.completed_storage(result).unwrap()
  assert_eq(@graph_storage.node_count(storage), 2)
  assert_eq(@graph_storage.edge_count(storage), 2)
  assert_eq(
    subgraph_checked_wire(
      @graph_storage.node_typed_key_at(storage, 0, 1).unwrap(),
    ),
    "1",
  )
  assert_eq(
    subgraph_checked_wire(
      @graph_storage.node_typed_key_at(storage, 1, 1).unwrap(),
    ),
    "2",
  )
  assert_eq(
    subgraph_checked_wire(
      @graph_storage.edge_typed_key_at(storage, 0, 0).unwrap(),
    ),
    "10",
  )
  assert_eq(
    subgraph_checked_wire(
      @graph_storage.edge_typed_key_at(storage, 1, 0).unwrap(),
    ),
    "11",
  )
  assert_eq(@graph_storage.edge_endpoints(storage, 0), Some((0, 1)))
  assert_eq(@graph_storage.edge_endpoints(storage, 1), Some((0, 1)))
  assert_true(@local_sga.cleanup_subgraph(active).unwrap())
  assert_true(@graphs.producer_read_available(input))
  assert_true(@graphs.discard_completed(result))
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let provider = @local_sga_provider.provider(
    { ..carrier_graph_storage_limits(), max_work: 10000, },
    8192L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
    snapshot_policy=Some({
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
    }),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  let selected = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    [
      @local_connector.managed_provider_carrier_input(
        @graphs.producer_read_view(input).unwrap(),
      ),
    ],
    10,
    1000,
  ).unwrap()
  let mut material = None
  for _ in 0..<1000 {
    match @local_connector.advance_managed_provider(selected, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) => {
        material = Some(value)
        break
      }
      _ => fail("subgraph provider failed")
    }
  }
  let material = material.unwrap()
  assert_true(@local_connector.cleanup_managed_provider(selected).unwrap())
  let snapshot = @carrier_runtime.material_prepare_snapshot(material)
    .unwrap()
    .unwrap()
  let saved = StringBuilder()
  let mut saved_complete = false
  for _ in 0..<10000 {
    let poll = (snapshot.advance_save)(1).unwrap()
    saved.write_string((snapshot.take_output)().unwrap())
    if poll.complete {
      saved_complete = true
      break
    }
  }
  assert_true(saved_complete)
  let content = (snapshot.content)().unwrap()
  (snapshot.release_source)(content.cid).unwrap()
  assert_false(@carrier_runtime.material_available(material))
  (snapshot.begin_reload)(saved.to_string(), () => true).unwrap()
  let mut reload_complete = false
  for _ in 0..<10000 {
    if (snapshot.advance_reload)(1).unwrap().complete {
      reload_complete = true
      break
    }
  }
  assert_true(reload_complete)
  let restored = (snapshot.take_material)().unwrap()
  let consumer = keyed_graph_receiver(
    owner,
    body="[{\"from\":\"g\",\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"id\"},\"fields\":[\"id\"]}}]",
  )
  let view = @carrier_runtime.material_prepare_view(
    restored, consumer, 0, owner,
  ).unwrap()
  assert_eq(@carrier_runtime.producer_view_edge_count(view), Some(2))
  let projected = @local_sga.start_match_edges_view(
    @bounded.control(),
    task_test_completion(consumer),
    prepared_sequence(consumer),
    0,
    view,
    10,
    { max_work: 10000, max_nodes: 1000, max_text_bytes: 10000, max_depth: 30, },
    20000,
    10000,
    10000,
    [],
  ).unwrap()
  let rows = finish_match_edges(projected).unwrap()
  assert_eq(@execution.completed_row_count(rows), 2)
  for row in 0..<2 {
    assert_eq(
      @execution.completed_output_row_wire(rows, row, 10000, 10000, 50).unwrap(),
      "{\"id\":{\"$json\":{\"definition\":\"E\",\"domain\":\"" +
      domain +
      "\",\"key\":[" +
      (10 + row).to_string() +
      "],\"key_types\":[{\"kind\":\"number\"}]}}}",
    )
  }
  assert_true(@local_sga.cleanup_match_edges(projected).unwrap())
  assert_true(@carrier_runtime.reclaim_material(restored))
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "Relation-selected subgraph cancels after output progress without revoking inputs" {
  let nodes = keyed_node_source(
    rows="[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"},{\"id\":2,\"tenant\":\"a\",\"name\":\"two\"}]",
  )
  let edges = keyed_edge_source(
    rows="[{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":2}]",
  )
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
    fail("Graph construction")
  }
  let selector_owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"key\"},\"where\":\"true\",\"fields\":[\"key\"]}}]",
  )
  let selector_graph = @graphs.prepare_producer_read(
    selector_owner, 0, graph_owner, graph,
  ).unwrap()
  let selector_run = @local_sga.start_match_nodes(
    @bounded.control(),
    task_test_completion(selector_owner),
    prepared_sequence(selector_owner),
    0,
    selector_graph,
    10,
    { max_work: 10000, max_nodes: 1000, max_text_bytes: 10000, max_depth: 30, },
    20000,
    10000,
    10000,
    [],
  ).unwrap()
  let selector_output = finish_match_nodes(selector_run).unwrap()
  assert_eq(@execution.completed_row_count(selector_output), 2)
  assert_true(@local_sga.cleanup_match_nodes(selector_run).unwrap())
  let owner = keyed_subgraph_relation_owner(graph_owner, selector_owner)
  let graph_input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let selector_input = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, selector_owner, selector_output).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let active = @local_sga.start_subgraph(
    control,
    prepared_sequence(owner),
    0,
    graph_input,
    Some(selector_input),
    { ..carrier_graph_storage_limits(), max_work: 10000, },
    8192L,
    () => true,
  ).unwrap()
  let mut progressed = false
  for _ in 0..<1000 {
    match @local_sga.advance_subgraph(active, 1).unwrap() {
      @local_sga.SubgraphContinue(progress~, work~) => {
        assert_true(work > 0L)
        if progress > 0L {
          progressed = true
          break
        }
      }
      _ => fail("subgraph did not yield after first node")
    }
  }
  assert_true(progressed)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_subgraph(active, 1)
    is Ok(@local_sga.SubgraphStopped(_, ..)),
  )
  assert_true(@local_sga.cleanup_subgraph(active).unwrap())
  assert_true(@graphs.producer_read_available(graph_input))
  assert_true(@execution.producer_read_available(selector_input))
  assert_true(@execution.completed_output_available(selector_output))
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "subgraph edge predicate retains nullable node values and independent edge keys" {
  let nodes = keyed_source_owner(
    "{\"id\":{\"type\":\"number\",\"nullable\":false},\"flag\":{\"type\":\"boolean\",\"nullable\":true}}",
    "[{\"id\":1,\"flag\":null},{\"id\":2,\"flag\":true}]",
  )
  let edges = keyed_source_owner(
    "{\"key\":{\"type\":\"number\",\"nullable\":false},\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false},\"flag\":{\"type\":\"boolean\",\"nullable\":false}}",
    "[{\"key\":10,\"src\":1,\"dst\":2,\"flag\":true},{\"key\":11,\"src\":1,\"dst\":2,\"flag\":false}]",
  )
  let graph_owner = keyed_bridge_owner(
    nodes,
    edges,
    body=Some(
      (
        #|[{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"flag","to":"f"}]}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"flag","to":"f"}]}}]}]},"as":"g"}]
      ),
    ),
  )
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
    fail("predicate Graph construction")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(contract)) else {
    fail("predicate Graph contract")
  }
  let domain = @carrier_contract.graph_domain(
    @carrier_contract.graph_definition(contract),
  )
  let identity = fn(key : Int) {
    "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[" +
    key.to_string() +
    "],\"key_types\":[{\"kind\":\"number\"}]}"
  }
  let owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"ids\":[" +
      identity(1) +
      "," +
      identity(2) +
      "]},\"edges\":\"f = TRUE\"}}]",
  )
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let active = @local_sga.start_subgraph(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    input,
    None,
    { ..carrier_graph_storage_limits(), max_work: 10000, },
    8192L,
    () => true,
  ).unwrap()
  let mut output = None
  for _ in 0..<1000 {
    match @local_sga.advance_subgraph(active, 1).unwrap() {
      @local_sga.SubgraphContinue(..) => ()
      @local_sga.SubgraphComplete(result, ..) => {
        output = Some(result)
        break
      }
      _ => fail("predicate subgraph failed")
    }
  }
  let output = output.unwrap()
  let storage = @graphs.completed_storage(output).unwrap()
  assert_eq(@graph_storage.node_count(storage), 2)
  assert_eq(@graph_storage.edge_count(storage), 1)
  assert_eq(
    subgraph_checked_wire(@graph_storage.node_property(storage, 0, 0).unwrap()),
    "null",
  )
  assert_eq(
    subgraph_checked_wire(@graph_storage.node_property(storage, 1, 0).unwrap()),
    "true",
  )
  assert_eq(
    subgraph_checked_wire(
      @graph_storage.edge_typed_key_at(storage, 0, 0).unwrap(),
    ),
    "10",
  )
  assert_true(@local_sga.cleanup_subgraph(active).unwrap())
  assert_true(@graphs.discard_completed(output))
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "ordinary Graph Program admits and selects a Relation-seeded subgraph" {
  let checked = query_checked_program_fixture(
    dag=true,
    local_carrier_graph_chain=true,
    local_carrier_graph_variant="current_subgraph",
    managed_publication=true,
  )
  let (run, issuer) = captured_graph_fixture(
    checked_program=Some(checked),
    local_carrier_graph_chain=true,
    local_carrier_graph_variant="current_subgraph",
    managed_publication=true,
  )
  let sequences = dispatch_test_generated(run)
  let mut selected = None
  for sequence in sequences {
    for step in 0..<@execution.generated_sequence_step_count(sequence) {
      if @execution.generated_sequence_step_at(sequence, step)
        is Some(@lower.GraphSubgraphStep(_)) {
        selected = @execution.select_generated_sequence_step(sequence, step)
      }
    }
  }
  let selected = selected.unwrap()
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    8192L,
    @execution.generated_sequence_capacity(
      selected,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, selected))
  @mock.close_mock_query_issuer(issuer)
}
