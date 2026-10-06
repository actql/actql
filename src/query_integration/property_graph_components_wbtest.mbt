///|
test "current Graph components preserve typed order and bounded ownership" {
  let prefix = "x".repeat(80)
  let first = prefix + "a"
  let second = prefix + "b"
  let source = keyed_source_owner(
    "{\"id\":{\"type\":\"string\",\"nullable\":false},\"src\":{\"type\":\"string\",\"nullable\":false},\"dst\":{\"type\":\"string\",\"nullable\":false}}",
    "[{\"id\":\"" +
    second +
    "\",\"src\":\"" +
    first +
    "\",\"dst\":\"" +
    second +
    "\"},{\"id\":\"" +
    first +
    "\",\"src\":\"" +
    first +
    "\",\"dst\":\"" +
    second +
    "\"}]",
  )
  let graph_body =
    #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"]}],"edges":[{"name":"E","from":"edges","key":["id"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]}}]},"as":"g"}]
  let owner = keyed_bridge_owner(source, source, body=Some(graph_body))
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    keyed_bridge_inputs(owner, source, source),
    { ..carrier_graph_storage_limits(), max_work: 10000, },
    10000L,
    1000,
    () => true,
  ).unwrap()
  let mut retained = None
  for _ in 0..<10000 {
    match @local_bridge.advance_rows_to_graph(construction, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(graph, ..) => {
        retained = Some(graph)
        break
      }
      _ => fail("component Graph construction failed")
    }
  }
  let graph = retained.unwrap()
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(schema)) else {
    fail("current Graph schema")
  }
  let domain = @carrier_contract.property_graph_domain(
    @carrier_contract.graph_property_definition(schema),
  )
  let identity = fn(key : String) {
    "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[\"" +
    key +
    "\"],\"key_types\":[{\"kind\":\"string\"}]}"
  }
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  for kind in ["weak", "strong"] {
    let receiver = keyed_graph_receiver(
      owner,
      body="[{\"from\":\"g\",\"components\":{\"kind\":\"" +
        kind +
        "\",\"max_output_rows\":2}}]",
    )
    let input = @graphs.prepare_producer_read(receiver, 0, owner, graph).unwrap()
    let start = fn(control, workspace) raise {
      @local_sga.start_components(
        control,
        task_test_completion(receiver),
        prepared_sequence(receiver),
        0,
        input,
        2,
        limits,
        workspace,
        10000,
        10000,
        [],
      )
    }
    // Fifteen slots per node, two per edge, three output fields, two
    // offset sentinels, and 51 resumable identity-check frames are reserved.
    assert_true(
      start(@bounded.control(), 89) is Err(@local_sga.ComponentsWorkspaceLimit),
    )
    let control = @bounded.control()
    let cancelled = start(control, 90).unwrap()
    for _ in 0..<45 {
      guard @local_sga.advance_components(cancelled, 1)
        is Ok(@local_sga.ComponentsContinue(work~, ..)) else {
        fail("component kernel did not yield")
      }
      assert_true(work > 0L)
    }
    assert_true(@bounded.request_cancel(control))
    assert_true(
      @local_sga.advance_components(cancelled, 1)
      is Ok(@local_sga.ComponentsStopped(_, ..)),
    )
    assert_true(@local_sga.cleanup_components(cancelled).unwrap())
    assert_true(@graphs.producer_read_available(input))
    let active = start(@bounded.control(), 90).unwrap()
    let mut completed = None
    for _ in 0..<10000 {
      match @local_sga.advance_components(active, 1).unwrap() {
        @local_sga.ComponentsContinue(work~, ..) => assert_true(work > 0L)
        @local_sga.ComponentsComplete(output, ..) => {
          completed = Some(output)
          break
        }
        _ => fail("component kernel failed")
      }
    }
    let output = completed.unwrap()
    for index, key in [first, second] {
      let component = if kind == "weak" { first } else { key }
      let size = if kind == "weak" { 2 } else { 1 }
      assert_eq(
        @execution.completed_output_row_wire(output, index, 10000, 10000, 50).unwrap(),
        "{\"component_id\":" +
        property_graph_expected_json_wire(identity(component)) +
        ",\"component_size\":" +
        size.to_string() +
        ",\"node_id\":" +
        property_graph_expected_json_wire(identity(key)) +
        "}",
      )
    }
    assert_true(@local_sga.cleanup_components(active).unwrap())
    if kind == "weak" {
      let view = @graphs.producer_read_view(input).unwrap()
      let viewed = fn(control, workspace) raise {
        @local_sga.start_components_view(
          control,
          task_test_completion(receiver),
          prepared_sequence(receiver),
          0,
          view,
          2,
          limits,
          workspace,
          10000,
          10000,
          [],
        )
      }
      assert_true(
        viewed(@bounded.control(), 89)
        is Err(@local_sga.ComponentsWorkspaceLimit),
      )
      let selected = viewed(@bounded.control(), 90).unwrap()
      let mut selected_output = None
      for _ in 0..<10000 {
        match @local_sga.advance_components(selected, 1).unwrap() {
          @local_sga.ComponentsContinue(..) => ()
          @local_sga.ComponentsComplete(value, ..) => {
            selected_output = Some(value)
            break
          }
          _ => fail("selected components failed")
        }
      }
      assert_eq(
        @execution.completed_output_row_wire(
          selected_output.unwrap(),
          0,
          10000,
          10000,
          50,
        ).unwrap(),
        "{\"component_id\":" +
        property_graph_expected_json_wire(identity(first)) +
        ",\"component_size\":2,\"node_id\":" +
        property_graph_expected_json_wire(identity(first)) +
        "}",
      )
      assert_true(@local_sga.cleanup_components(selected).unwrap())
      let view_control = @bounded.control()
      let selected_cancel = viewed(view_control, 90).unwrap()
      for _ in 0..<45 {
        guard @local_sga.advance_components(selected_cancel, 1)
          is Ok(@local_sga.ComponentsContinue(work~, ..)) else {
          fail("selected component kernel did not yield")
        }
        assert_true(work > 0L)
      }
      assert_true(@bounded.request_cancel(view_control))
      assert_true(
        @local_sga.advance_components(selected_cancel, 1)
        is Ok(@local_sga.ComponentsStopped(_, ..)),
      )
      assert_true(@local_sga.cleanup_components(selected_cancel).unwrap())
      assert_true(@graphs.producer_read_available(input))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "components distinguish a directed cycle feeder and isolated node" {
  let nodes = keyed_source_owner(
    "{\"id\":{\"type\":\"number\",\"nullable\":false}}", "[{\"id\":4},{\"id\":3},{\"id\":2},{\"id\":1}]",
  )
  let edges = keyed_source_owner(
    "{\"key\":{\"type\":\"number\",\"nullable\":false},\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}}",
    "[{\"key\":12,\"src\":3,\"dst\":2},{\"key\":11,\"src\":2,\"dst\":1},{\"key\":10,\"src\":1,\"dst\":2}]",
  )
  let body =
    #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]}}]},"as":"g"}]
  let owner = keyed_bridge_owner(nodes, edges, body=Some(body))
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    keyed_bridge_inputs(owner, nodes, edges),
    { ..carrier_graph_storage_limits(), max_work: 10000, },
    10000L,
    1000,
    () => true,
  ).unwrap()
  let graph = match
    keyed_bridge_terminal(construction, max_fixture_steps=10000) {
    @local_bridge.Complete(value, ..) => value
    _ => fail("cycle Graph construction failed")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(schema)) else {
    fail("typed cycle Graph schema")
  }
  let domain = @carrier_contract.property_graph_domain(
    @carrier_contract.graph_property_definition(schema),
  )
  let identity = fn(key : Int) {
    "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[" +
    key.to_string() +
    "],\"key_types\":[{\"kind\":\"number\"}]}"
  }
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  for kind in ["weak", "strong"] {
    let receiver = keyed_graph_receiver(
      owner,
      body="[{\"from\":\"g\",\"components\":{\"kind\":\"" +
        kind +
        "\",\"max_output_rows\":4}}]",
    )
    let input = @graphs.prepare_producer_read(receiver, 0, owner, graph).unwrap()
    let active = @local_sga.start_components(
      @bounded.control(),
      task_test_completion(receiver),
      prepared_sequence(receiver),
      0,
      input,
      4,
      limits,
      200,
      10000,
      10000,
      [],
    ).unwrap()
    let mut output = None
    for _ in 0..<10000 {
      match @local_sga.advance_components(active, 1).unwrap() {
        @local_sga.ComponentsContinue(work~, ..) => assert_true(work > 0L)
        @local_sga.ComponentsComplete(value, ..) => {
          output = Some(value)
          break
        }
        _ => fail("cycle component execution failed")
      }
    }
    let output = output.unwrap()
    let expected_rows = if kind == "weak" {
      [(0, 1, 1, 3), (1, 2, 1, 3), (2, 3, 1, 3), (3, 4, 4, 1)]
    } else {
      [(0, 1, 1, 2), (1, 2, 1, 2), (2, 3, 3, 1), (3, 4, 4, 1)]
    }
    for (index, node, component, size) in expected_rows {
      assert_eq(
        @execution.completed_output_row_wire(output, index, 10000, 10000, 50).unwrap(),
        "{\"component_id\":" +
        property_graph_expected_json_wire(identity(component)) +
        ",\"component_size\":" +
        size.to_string() +
        ",\"node_id\":" +
        property_graph_expected_json_wire(identity(node)) +
        "}",
      )
    }
    assert_true(@local_sga.cleanup_components(active).unwrap())
    assert_true(@graphs.producer_read_available(input))
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "empty components admit exact control work and reject one short" {
  let source = keyed_source_owner(
    "{\"id\":{\"type\":\"number\",\"nullable\":false},\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}}",
    "[]",
  )
  let body =
    #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"]}],"edges":[{"name":"E","from":"edges","key":["id"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]}}]},"as":"g"}]
  let owner = keyed_bridge_owner(source, source, body=Some(body))
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    keyed_bridge_inputs(owner, source, source),
    { ..carrier_graph_storage_limits(), max_work: 10000, },
    10000L,
    1000,
    () => true,
  ).unwrap()
  let graph = match
    keyed_bridge_terminal(construction, max_fixture_steps=10000) {
    @local_bridge.Complete(value, ..) => value
    _ => fail("empty Graph construction failed")
  }
  let receiver = keyed_graph_receiver(
    owner,
    body="[{\"from\":\"g\",\"components\":{\"kind\":\"weak\"}}]",
  )
  let input = @graphs.prepare_producer_read(receiver, 0, owner, graph).unwrap()
  let start = fn(work : Int) raise {
    @local_sga.start_components(
      @bounded.control(),
      task_test_completion(receiver),
      prepared_sequence(receiver),
      0,
      input,
      0,
      { max_work: work, max_nodes: 0, max_text_bytes: 0, max_depth: 0, },
      100,
      10000,
      10000,
      [],
      control_work_limit=Some(100),
    )
  }
  let short = start(0).unwrap()
  assert_true(
    @local_sga.advance_components(short, 1)
    is Ok(@local_sga.ComponentsFailed(@local_sga.ComponentsWorkLimit, ..)),
  )
  assert_true(@local_sga.cleanup_components(short).unwrap())
  assert_true(@graphs.producer_read_available(input))
  let exact = start(1).unwrap()
  let mut completed = None
  for _ in 0..<30 {
    match @local_sga.advance_components(exact, 1).unwrap() {
      @local_sga.ComponentsContinue(..) => ()
      @local_sga.ComponentsComplete(output, ..) => {
        completed = Some(output)
        break
      }
      @local_sga.ComponentsFailed(@local_sga.ComponentsWorkLimit, ..) =>
        fail("exact empty components exceeded work")
      @local_sga.ComponentsFailed(@local_sga.ComponentsOutput(_), ..) =>
        fail("exact empty components output failed")
      @local_sga.ComponentsFailed(@local_sga.ComponentsCompletion(_), ..) =>
        fail("exact empty components completion failed")
      _ => fail("exact empty components failed")
    }
  }
  let output = completed.unwrap()
  assert_true(
    @execution.completed_output_row_wire(output, 0, 100, 100, 10) is Err(_),
  )
  assert_true(@local_sga.cleanup_components(exact).unwrap())
  let view = @graphs.producer_read_view(input).unwrap()
  let start_view = fn(work : Int) raise {
    @local_sga.start_components_view(
      @bounded.control(),
      task_test_completion(receiver),
      prepared_sequence(receiver),
      0,
      view,
      0,
      { max_work: work, max_nodes: 0, max_text_bytes: 0, max_depth: 0, },
      100,
      10000,
      10000,
      [],
      control_work_limit=Some(100),
    )
  }
  let view_short = start_view(0).unwrap()
  assert_true(
    @local_sga.advance_components(view_short, 1)
    is Ok(@local_sga.ComponentsFailed(@local_sga.ComponentsWorkLimit, ..)),
  )
  assert_true(@local_sga.cleanup_components(view_short).unwrap())
  let view_exact = start_view(1).unwrap()
  let mut view_completed = None
  for _ in 0..<30 {
    match @local_sga.advance_components(view_exact, 1).unwrap() {
      @local_sga.ComponentsContinue(..) => ()
      @local_sga.ComponentsComplete(value, ..) => {
        view_completed = Some(value)
        break
      }
      _ => fail("exact viewed empty components failed")
    }
  }
  assert_true(
    @execution.completed_output_row_wire(
      view_completed.unwrap(),
      0,
      100,
      100,
      10,
    )
    is Err(_),
  )
  assert_true(@local_sga.cleanup_components(view_exact).unwrap())
  assert_true(@graphs.producer_read_available(input))
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
