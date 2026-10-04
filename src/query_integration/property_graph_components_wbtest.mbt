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
        identity(component) +
        ",\"component_size\":" +
        size.to_string() +
        ",\"node_id\":" +
        identity(key) +
        "}",
      )
    }
    assert_true(@local_sga.cleanup_components(active).unwrap())
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
