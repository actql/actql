///|
fn long_graph_start_admission_fixture(relation : Bool) -> Unit raise {
  // Nine independently bounded Text fragments, including data Unicode and
  // line endings. The selector must borrow this value, not normalize it.
  let text = String::make(513, 'x') + "e\u0301\r\n😀"
  let writer = @encode.writer(10000, 1000, 50)
  @encode.string_value(writer, text)
  let text_wire = @encode.finish(writer)
  let nodes = keyed_node_source(
    rows="[{\"id\":1,\"tenant\":" + text_wire + ",\"name\":\"one\"}]",
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
  guard keyed_bridge_terminal(construction, max_fixture_steps=10000)
    is @local_bridge.Complete(graph, ..) else {
    abort("long-key Graph construction failed")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(carrier)) else {
    abort("long-key Graph contract missing")
  }
  let domain = @carrier_contract.graph_domain(
    @carrier_contract.graph_definition(carrier),
  )
  let identity = "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[" +
    text_wire +
    ",1],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}"
  let literal = @encode.writer(10000, 1000, 50)
  @encode.string_value(literal, identity)
  let selector_owner = keyed_source_owner(
    "{\"keep\":{\"type\":\"boolean\",\"nullable\":false}}",
    "[{\"keep\":true}]",
    suffix=",{\"derive\":{\"key\":{\"typed_literal\":{\"type\":\"json\",\"value\":" +
      @encode.finish(literal) +
      "}}}}",
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
  let body = "[{\"from\":\"g\",\"reach\":{\"start\":" +
    (if relation { "{\"from\":\"seeds\",\"id\":\"key\"}" } else { identity }) +
    ",\"direction\":\"out\",\"max_depth\":1}}]"
  let owner = if relation {
    keyed_relation_path_owner(
      graph_owner,
      selector_owner,
      selector_step=1,
      body~,
    )
  } else {
    keyed_graph_receiver(graph_owner, body~)
  }
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let selectors = if relation {
    [
      @execution.prepare_producer_read(
        owner,
        @execution.bind_completed_input(
          owner, 1, selector_owner, selector_output,
        ).unwrap(),
        100,
        10000,
      ).unwrap(),
    ]
  } else {
    []
  }
  let completion = task_test_completion(owner)
  let start = fn(control, work, workspace) {
    @local_sga.start_traverse_view(
      control,
      completion,
      prepared_sequence(owner),
      0,
      @graphs.producer_read_view(input).unwrap(),
      1,
      { max_work: work, max_nodes: 1000, max_text_bytes: 10000, max_depth: 50, },
      workspace,
      10000,
      10000,
      selectors,
    ).unwrap()
  }
  let control = @bounded.control()
  let active = start(control, 100000, 10000)
  // The Boolean selector entry uses one slot. ResolveStarts must only stage
  // the root, cursor and first frame, not finish admission or lookup.
  for _ in 0..<2 {
    assert_true(
      @local_sga.advance_traverse(active, 1).unwrap()
      is @local_sga.TraverseContinue(..),
    )
  }
  assert_eq(@local_sga.traverse_private_workspace_usage(active).0, 1 + 3)
  // Polls 13..21 of the identity recheck scan the long key. Cancellation at
  // this prefix therefore interrupts the value scan, not row publication.
  for _ in 0..<14 {
    assert_true(
      @local_sga.advance_traverse(active, 1).unwrap()
      is @local_sga.TraverseContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(@graphs.producer_read_available(input))
  for selector in selectors {
    assert_true(@execution.producer_read_available(selector))
  }
  assert_true(
    @local_sga.advance_traverse(active, 1).unwrap()
    is @local_sga.TraverseStopped(@bounded.Cancelled, work=16L, ..),
  )
  assert_true(@local_sga.traverse_stopped(active))
  assert_true(@local_sga.cleanup_traverse(active).unwrap())
  assert_false(@local_sga.cleanup_traverse(active).unwrap())
  assert_eq(@local_sga.traverse_private_workspace_usage(active).0, 0)
  assert_eq(@local_sga.traverse_private_entry_count(active), 0)
  // Independent accounting: the original two-component identity has 32 tree
  // polls and one completion poll. Replacing its one-unit key with 519 UTF-16
  // units adds eight Text polls. Input starts repeat the same receiving-schema
  // admission before the nonnullable Graph identity admission.
  assert_eq(text.length(), 519)
  assert_eq(domain.length(), 71)
  let identity_recheck = 32 + 1 + 8
  let start_admission = identity_recheck +
    1 +
    (if relation { identity_recheck } else { 0 })
  // Output rechecks have two long identities (40 tree polls each), a number,
  // three reads/terminal polls, and setup. Each identity's value charge has
  // 24 base polls plus nine long-Text fragments; names/values and commit stay
  // unchanged. State transitions outside admission/output contribute ten.
  let row_control = 3 + 2 * (32 + 8) + 1 + 3 + 1 + (6 + 2 * (24 + 9) + 1)
  let control_work = 10 + start_admission + row_control
  // One row, one number, and two 11-node identities. The authored key is
  // 522 UTF-8 bytes rather than one byte; fixed identity Text is 50+71 bytes.
  let output_work = 1 + 1 + 2 * 11 + 2 * (50 + 71 + 521) + (5 + 7 + 8)
  let exact_work = control_work + output_work
  // Output retains three indices, four row slots and three traversal frames.
  // Start admission separately peaks at selector (1), root/cursor (2), four
  // frames plus one pre-reserved growth slot: eight, less than output's ten.
  let exact_workspace = 3 + 4 + 3
  for quantum in [1, 7, 256] {
    let active = start(@bounded.control(), exact_work, exact_workspace)
    let spent = Ref(0L)
    let output = finish_traverse(active, quantum~, spent_work=Some(spent)).unwrap()
    assert_eq(spent.val, control_work.to_int64())
    assert_eq(
      @local_sga.traverse_private_workspace_usage(active).1,
      exact_workspace,
    )
    assert_eq(@execution.completed_row_count(output), 1)
    let id = graph_expected_json_wire(identity)
    assert_eq(
      @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
      "{\"depth\":0,\"node_id\":" + id + ",\"start_id\":" + id + "}",
    )
    assert_true(@local_sga.cleanup_traverse(active).unwrap())
    assert_eq(@local_sga.traverse_private_entry_count(active), 0)
    assert_true(@graphs.producer_read_available(input))
    for
      (work, workspace, expected) in [
        (exact_work - 1, exact_workspace, @local_sga.TraversePathsWorkLimit),
        (
          exact_work,
          exact_workspace - 1,
          @local_sga.TraversePathsWorkspaceLimit,
        ),
        // Fail during admission, before membership lookup or output assembly.
        (exact_work, 1 + 2 + 4, @local_sga.TraversePathsWorkspaceLimit),
      ] {
      let rejected = start(@bounded.control(), work, workspace)
      assert_eq(
        finish_traverse(rejected, quantum~).unwrap_err(),
        @local_sga.TraversePathIssue(expected),
      )
      assert_true(@local_sga.cleanup_traverse(rejected).unwrap())
      assert_false(@local_sga.cleanup_traverse(rejected).unwrap())
      assert_eq(@local_sga.traverse_private_workspace_usage(rejected).0, 0)
      assert_eq(@local_sga.traverse_private_entry_count(rejected), 0)
      assert_true(@graphs.producer_read_available(input))
      for selector in selectors {
        assert_true(@execution.producer_read_available(selector))
      }
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "literal Graph starts yield inside long identity admission" {
  long_graph_start_admission_fixture(false)
}

///|
test "Relation Graph starts yield inside long identity admission" {
  long_graph_start_admission_fixture(true)
}
