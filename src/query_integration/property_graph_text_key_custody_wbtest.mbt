///|
test "typed node and edge identity sorting yields during long comparisons and preserves input on stop" {
  let prefix = "x".repeat(160)
  let first = prefix + "a"
  let second = prefix + "b"
  let source = keyed_source_owner(
    "{\"id\":{\"type\":\"string\",\"nullable\":false}}",
    "[{\"id\":\"" + second + "\"},{\"id\":\"" + first + "\"}]",
  )
  let graph_body =
    #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"]}],"edges":[{"name":"E","from":"edges","key":["id"],"source":{"definition":"N","key":["id"]},"target":{"definition":"N","key":["id"]}}]},"as":"g"}]
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
      _ => fail("long typed-key constructor failed")
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
  for edges in [false, true] {
    let definition = if edges { "E" } else { "N" }
    let operation = if edges { "match_edges" } else { "match_nodes" }
    let receiver = keyed_graph_receiver(
      owner,
      body="[{\"from\":\"g\",\"" +
        operation +
        "\":{\"definition\":\"" +
        definition +
        "\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}}]",
    )
    let input = @graphs.prepare_producer_read(receiver, 0, owner, graph).unwrap()
    let control = @bounded.control()
    let sequence = prepared_sequence(receiver)
    let preparation = task_test_completion(receiver)
    let limits : @execution.ValueLimits = {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 50,
    }
    if edges {
      let active = @local_sga.start_match_edges(
        control,
        preparation,
        sequence,
        0,
        input,
        2,
        limits,
        100,
        10000,
        10000,
        [],
      ).unwrap()
      for _ in 0..<60 {
        guard @local_sga.advance_match_edges(active, 1)
          is Ok(@local_sga.MatchEdgesContinue(work~, ..)) else {
          fail("long edge comparison must yield")
        }
        assert_true(work > 0L)
      }
      assert_true(@bounded.request_cancel(control))
      assert_true(
        @local_sga.advance_match_edges(active, 1)
        is Ok(@local_sga.MatchEdgesStopped(_, ..)),
      )
      assert_true(@local_sga.cleanup_match_edges(active).unwrap())
      assert_false(@local_sga.cleanup_match_edges(active).unwrap())
      assert_true(@graphs.producer_read_available(input))
      let complete = @local_sga.start_match_edges(
        @bounded.control(),
        preparation,
        sequence,
        0,
        input,
        2,
        limits,
        100,
        10000,
        10000,
        [],
      ).unwrap()
      let output = finish_match_edges(complete).unwrap()
      for index, key in [first, second] {
        assert_eq(
          @execution.completed_output_row_wire(output, index, 10000, 10000, 50).unwrap(),
          "{\"element\":{\"definition\":\"E\",\"domain\":\"" +
          domain +
          "\",\"key\":[\"" +
          key +
          "\"],\"key_types\":[{\"kind\":\"string\"}]}}",
        )
      }
      assert_true(@local_sga.cleanup_match_edges(complete).unwrap())
    } else {
      let active = @local_sga.start_match_nodes(
        control,
        preparation,
        sequence,
        0,
        input,
        2,
        limits,
        100,
        10000,
        10000,
        [],
      ).unwrap()
      for _ in 0..<60 {
        guard @local_sga.advance_match_nodes(active, 1)
          is Ok(@local_sga.MatchNodesContinue(work~, ..)) else {
          fail("long node comparison must yield")
        }
        assert_true(work > 0L)
      }
      assert_true(@bounded.request_cancel(control))
      assert_true(
        @local_sga.advance_match_nodes(active, 1)
        is Ok(@local_sga.MatchNodesStopped(_, ..)),
      )
      assert_true(@local_sga.cleanup_match_nodes(active).unwrap())
      assert_false(@local_sga.cleanup_match_nodes(active).unwrap())
      assert_true(@graphs.producer_read_available(input))
      let complete = @local_sga.start_match_nodes(
        @bounded.control(),
        preparation,
        sequence,
        0,
        input,
        2,
        limits,
        100,
        10000,
        10000,
        [],
      ).unwrap()
      let output = finish_match_nodes(complete).unwrap()
      for index, key in [first, second] {
        assert_eq(
          @execution.completed_output_row_wire(output, index, 10000, 10000, 50).unwrap(),
          "{\"element\":{\"definition\":\"N\",\"domain\":\"" +
          domain +
          "\",\"key\":[\"" +
          key +
          "\"],\"key_types\":[{\"kind\":\"string\"}]}}",
        )
      }
      assert_true(@local_sga.cleanup_match_nodes(complete).unwrap())
    }
  }
  let identity = fn(key : String) {
    "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[\"" +
    key +
    "\"],\"key_types\":[{\"kind\":\"string\"}]}"
  }
  let receiver = keyed_graph_receiver(
    owner,
    body="[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
      identity(second) +
      "," +
      identity(first) +
      "]},\"path_mode\":\"trail\",\"min_hops\":0,\"max_hops\":1,\"direction\":\"out\",\"emit\":\"paths\"}}]",
  )
  let input = @graphs.prepare_producer_read(receiver, 0, owner, graph).unwrap()
  let preparation = task_test_completion(receiver)
  let start = fn(control) {
    @local_sga.start_traverse(
      control,
      preparation,
      prepared_sequence(receiver),
      0,
      input,
      4,
      {
        max_work: 100000,
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 50,
      },
      100,
      10000,
      10000,
      [],
    ).unwrap()
  }
  let control = @bounded.control()
  let active = start(control)
  for _ in 0..<60 {
    guard @local_sga.advance_traverse(active, 1)
      is Ok(@local_sga.TraverseContinue(work~, ..)) else {
      fail("long start comparison must yield")
    }
    assert_true(work > 0L)
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_traverse(active, 1)
    is Ok(@local_sga.TraverseStopped(_, ..)),
  )
  assert_true(@local_sga.cleanup_traverse(active).unwrap())
  assert_false(@local_sga.cleanup_traverse(active).unwrap())
  assert_eq(@local_sga.traverse_private_entry_count(active), 0)
  assert_true(@graphs.producer_read_available(input))
  let complete = start(@bounded.control())
  let output = finish_traverse(complete).unwrap()
  assert_eq(@execution.completed_row_count(output), 4)
  for index, key in [first, second] {
    let node = identity(key)
    let edge = "{\"definition\":\"E\",\"domain\":\"" +
      domain +
      "\",\"key\":[\"" +
      key +
      "\"],\"key_types\":[{\"kind\":\"string\"}]}"
    for depth in [0, 1] {
      let edge_ids = if depth == 0 { "[]" } else { "[" + edge + "]" }
      let node_ids = if depth == 0 {
        "[" + node + "]"
      } else {
        "[" + node + "," + node + "]"
      }
      assert_eq(
        @execution.completed_output_row_wire(
          output,
          index * 2 + depth,
          10000,
          10000,
          50,
        ).unwrap(),
        "{\"edge_ids\":" +
        edge_ids +
        ",\"end_id\":" +
        node +
        ",\"hop_count\":" +
        depth.to_string() +
        ",\"node_ids\":" +
        node_ids +
        ",\"start_id\":" +
        node +
        "}",
      )
    }
  }
  assert_true(@local_sga.cleanup_traverse(complete).unwrap())
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "Graph bounds yields during typed identity ordering and rejects partial output" {
  let prefix = "x".repeat(160)
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
      _ => fail("diagnostic Graph construction failed")
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
  let receiver = keyed_graph_receiver(
    owner,
    body="[{\"from\":\"g\",\"graph_bounds\":{\"max_degree\":1}}]",
  )
  let input = @graphs.prepare_producer_read(receiver, 0, owner, graph).unwrap()
  let preparation = task_test_completion(receiver)
  let sequence = prepared_sequence(receiver)
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  let start = fn(control, rows, workspace, control_work) {
    @local_sga.start_graph_bounds(
      control,
      preparation,
      sequence,
      0,
      input,
      rows,
      limits,
      workspace,
      10000,
      10000,
      [],
      control_work_limit=Some(control_work),
    )
  }
  // Two node degree cells, two sort entries, two scratch entries and four
  // pending output fields are live at once.
  assert_true(
    start(@bounded.control(), 2, 9, 10000)
    is Err(@local_sga.GraphBoundsWorkspaceLimit),
  )
  let control = @bounded.control()
  let cancelled = match start(control, 2, 10, 10000) {
    Ok(value) => value
    Err(@local_sga.GraphBoundsWorkspaceLimit) => fail("workspace limit")
    Err(@local_sga.InvalidGraphBoundsKernel) => fail("invalid kernel")
    Err(@local_sga.GraphBoundsInputUnavailable) => fail("input unavailable")
    Err(@local_sga.GraphBoundsOutput(_)) => fail("output admission")
    Err(@local_sga.GraphBoundsCompletion(_)) => fail("completion admission")
    Err(_) => fail("other start failure")
  }
  for _ in 0..<60 {
    guard @local_sga.advance_graph_bounds(cancelled, 1)
      is Ok(@local_sga.GraphBoundsContinue(work~, ..)) else {
      fail("typed bounds comparison must yield")
    }
    assert_true(work > 0L)
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_graph_bounds(cancelled, 1)
    is Ok(@local_sga.GraphBoundsStopped(_, ..)),
  )
  assert_true(@local_sga.cleanup_graph_bounds(cancelled).unwrap())
  assert_false(@local_sga.cleanup_graph_bounds(cancelled).unwrap())
  assert_true(@graphs.producer_read_available(input))
  let finish = fn(active) raise {
    for _ in 0..<10000 {
      match @local_sga.advance_graph_bounds(active, 1).unwrap() {
        @local_sga.GraphBoundsContinue(work~, ..) => assert_true(work > 0L)
        @local_sga.GraphBoundsComplete(output, ..) => return output
        _ => fail("bounded Graph diagnostics failed")
      }
    }
    fail("bounded Graph diagnostics exceeded the fixture allowance")
  }
  // Two node and two edge units, 163 merge units (the first comparison unit
  // advances both the one-character definition and the first key unit), two
  // copy units, four candidate units, ten field/commit units and one finish
  // unit require 184 control units independently of the returned work count.
  let complete = start(@bounded.control(), 2, 10, 184).unwrap()
  let output = finish(complete)
  let identity = fn(key : String) {
    "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[\"" +
    key +
    "\"],\"key_types\":[{\"kind\":\"string\"}]}"
  }
  for index, key in [first, second] {
    assert_eq(
      @execution.completed_output_row_wire(output, index, 10000, 10000, 50).unwrap(),
      "{\"actual\":2,\"kind\":\"degree\",\"max\":1,\"node_id\":" +
      identity(key) +
      "}",
    )
  }
  assert_true(@local_sga.cleanup_graph_bounds(complete).unwrap())
  let one_short = start(@bounded.control(), 1, 10, 10000).unwrap()
  let mut rejected = false
  for _ in 0..<10000 {
    match @local_sga.advance_graph_bounds(one_short, 1).unwrap() {
      @local_sga.GraphBoundsContinue(..) => ()
      @local_sga.GraphBoundsFailed(
        @local_sga.GraphBoundsOutput(@execution.CaptureLimit),
        ..
      ) => {
        rejected = true
        break
      }
      _ => fail("one-short output limit returned an unrelated result")
    }
  }
  assert_true(rejected)
  assert_true(@local_sga.cleanup_graph_bounds(one_short).unwrap())
  let work_short = start(@bounded.control(), 2, 10, 183).unwrap()
  let mut work_rejected = false
  for _ in 0..<10000 {
    match @local_sga.advance_graph_bounds(work_short, 1).unwrap() {
      @local_sga.GraphBoundsContinue(..) => ()
      @local_sga.GraphBoundsFailed(@local_sga.GraphBoundsWorkLimit, ..) => {
        work_rejected = true
        break
      }
      @local_sga.GraphBoundsComplete(_, ..) => fail("one-short work completed")
      @local_sga.GraphBoundsStopped(_, ..) => fail("one-short work stopped")
      @local_sga.GraphBoundsFailed(@local_sga.GraphBoundsOutput(_), ..) =>
        fail("one-short work hit output limit")
      @local_sga.GraphBoundsFailed(@local_sga.GraphBoundsCompletion(_), ..) =>
        fail("one-short work hit completion limit")
      @local_sga.GraphBoundsFailed(_, ..) =>
        fail("one-short work hit other failure")
    }
  }
  assert_true(work_rejected)
  assert_true(@local_sga.cleanup_graph_bounds(work_short).unwrap())
  let view = @graphs.producer_read_view(input).unwrap()
  assert_true(
    @local_sga.start_graph_bounds_view(
      @bounded.control(),
      preparation,
      sequence,
      0,
      view,
      2,
      limits,
      9,
      10000,
      10000,
      [],
      control_work_limit=Some(184),
    )
    is Err(@local_sga.GraphBoundsWorkspaceLimit),
  )
  let viewed = @local_sga.start_graph_bounds_view(
    @bounded.control(),
    preparation,
    sequence,
    0,
    view,
    2,
    limits,
    10,
    10000,
    10000,
    [],
    control_work_limit=Some(184),
  ).unwrap()
  let viewed_output = finish(viewed)
  assert_eq(
    @execution.completed_output_row_wire(viewed_output, 0, 10000, 10000, 50).unwrap(),
    "{\"actual\":2,\"kind\":\"degree\",\"max\":1,\"node_id\":" +
    identity(first) +
    "}",
  )
  assert_true(@local_sga.cleanup_graph_bounds(viewed).unwrap())
  let viewed_short = @local_sga.start_graph_bounds_view(
    @bounded.control(),
    preparation,
    sequence,
    0,
    view,
    2,
    limits,
    10,
    10000,
    10000,
    [],
    control_work_limit=Some(183),
  ).unwrap()
  let mut view_work_rejected = false
  for _ in 0..<10000 {
    match @local_sga.advance_graph_bounds(viewed_short, 1).unwrap() {
      @local_sga.GraphBoundsContinue(..) => ()
      @local_sga.GraphBoundsFailed(@local_sga.GraphBoundsWorkLimit, ..) => {
        view_work_rejected = true
        break
      }
      _ => fail("one-short viewed bounds returned an unrelated result")
    }
  }
  assert_true(view_work_rejected)
  assert_true(@local_sga.cleanup_graph_bounds(viewed_short).unwrap())
  assert_true(@graphs.producer_read_available(input))
  for
    (direction, first_degree, second_degree) in [
      ("in", 0, 2),
      ("out", 2, 0),
      ("both", 2, 2),
    ] {
    let degree_owner = keyed_graph_receiver(
      owner,
      body="[{\"from\":\"g\",\"degree\":{\"direction\":\"" + direction + "\"}}]",
    )
    let degree_input = @graphs.prepare_producer_read(
      degree_owner, 0, owner, graph,
    ).unwrap()
    if direction == "in" {
      assert_true(
        @local_sga.start_graph_degree(
          @bounded.control(),
          task_test_completion(degree_owner),
          prepared_sequence(degree_owner),
          0,
          degree_input,
          2,
          limits,
          7,
          10000,
          10000,
          [],
          control_work_limit=Some(178),
        )
        is Err(@local_sga.GraphBoundsWorkspaceLimit),
      )
    }
    // Two node and two edge units, 163 typed merge units, two copy units,
    // two selections, six field/commit units and one finish unit: 178.
    let degree = @local_sga.start_graph_degree(
      @bounded.control(),
      task_test_completion(degree_owner),
      prepared_sequence(degree_owner),
      0,
      degree_input,
      2,
      limits,
      8,
      10000,
      10000,
      [],
      control_work_limit=Some(178),
    ).unwrap()
    let mut degree_output = None
    for _ in 0..<10000 {
      match @local_sga.advance_graph_degree(degree, 1).unwrap() {
        @local_sga.GraphDegreeContinue(..) => ()
        @local_sga.GraphDegreeComplete(value, ..) => {
          degree_output = Some(value)
          break
        }
        _ => fail("directional Graph degree failed")
      }
    }
    let degree_output = degree_output.unwrap()
    for
      (index, key, expected_degree) in [
        (0, first, first_degree),
        (1, second, second_degree),
      ] {
      assert_eq(
        @execution.completed_output_row_wire(
          degree_output, index, 10000, 10000, 50,
        ).unwrap(),
        "{\"degree\":" +
        expected_degree.to_string() +
        ",\"node\":" +
        identity(key) +
        "}",
      )
    }
    assert_true(@local_sga.cleanup_graph_degree(degree).unwrap())
    if direction == "in" {
      let work_short = @local_sga.start_graph_degree(
        @bounded.control(),
        task_test_completion(degree_owner),
        prepared_sequence(degree_owner),
        0,
        degree_input,
        2,
        limits,
        8,
        10000,
        10000,
        [],
        control_work_limit=Some(177),
      ).unwrap()
      let mut rejected = false
      for _ in 0..<10000 {
        match @local_sga.advance_graph_degree(work_short, 1).unwrap() {
          @local_sga.GraphDegreeContinue(..) => ()
          @local_sga.GraphDegreeFailed(@local_sga.GraphBoundsWorkLimit, ..) => {
            rejected = true
            break
          }
          _ => fail("one-short degree work returned an unrelated result")
        }
      }
      assert_true(rejected)
      assert_true(@local_sga.cleanup_graph_degree(work_short).unwrap())
      let degree_view = @graphs.producer_read_view(degree_input).unwrap()
      assert_true(
        @local_sga.start_graph_degree_view(
          @bounded.control(),
          task_test_completion(degree_owner),
          prepared_sequence(degree_owner),
          0,
          degree_view,
          2,
          limits,
          7,
          10000,
          10000,
          [],
          control_work_limit=Some(178),
        )
        is Err(@local_sga.GraphBoundsWorkspaceLimit),
      )
      let viewed = @local_sga.start_graph_degree_view(
        @bounded.control(),
        task_test_completion(degree_owner),
        prepared_sequence(degree_owner),
        0,
        degree_view,
        2,
        limits,
        8,
        10000,
        10000,
        [],
        control_work_limit=Some(178),
      ).unwrap()
      let mut viewed_complete = false
      for _ in 0..<10000 {
        match @local_sga.advance_graph_degree(viewed, 1).unwrap() {
          @local_sga.GraphDegreeContinue(..) => ()
          @local_sga.GraphDegreeComplete(output, ..) => {
            assert_eq(
              @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
              "{\"degree\":0,\"node\":" + identity(first) + "}",
            )
            viewed_complete = true
            break
          }
          _ => fail("viewed Graph degree failed")
        }
      }
      assert_true(viewed_complete)
      assert_true(@local_sga.cleanup_graph_degree(viewed).unwrap())
      let viewed_short = @local_sga.start_graph_degree_view(
        @bounded.control(),
        task_test_completion(degree_owner),
        prepared_sequence(degree_owner),
        0,
        degree_view,
        2,
        limits,
        8,
        10000,
        10000,
        [],
        control_work_limit=Some(177),
      ).unwrap()
      let mut view_work_rejected = false
      for _ in 0..<10000 {
        match @local_sga.advance_graph_degree(viewed_short, 1).unwrap() {
          @local_sga.GraphDegreeContinue(..) => ()
          @local_sga.GraphDegreeFailed(@local_sga.GraphBoundsWorkLimit, ..) => {
            view_work_rejected = true
            break
          }
          _ => fail("one-short viewed degree returned an unrelated result")
        }
      }
      assert_true(view_work_rejected)
      assert_true(@local_sga.cleanup_graph_degree(viewed_short).unwrap())
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
