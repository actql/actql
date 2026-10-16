///|
test "degree executes node_id rows and retains the original atomic output limit" {
  let source = keyed_source_owner(
    "{\"id\":{\"type\":\"string\",\"nullable\":false},\"src\":{\"type\":\"string\",\"nullable\":false},\"dst\":{\"type\":\"string\",\"nullable\":false}}",
    "[{\"id\":\"b\",\"src\":\"a\",\"dst\":\"b\"},{\"id\":\"a\",\"src\":\"a\",\"dst\":\"b\"}]",
  )
  let body =
    #|[{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"]}],"edges":[{"name":"E","from":"edges","key":["id"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]}}]},"as":"g"}]
  let owner = keyed_bridge_owner(source, source, body=Some(body))
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    keyed_bridge_inputs(owner, source, source),
    { ..carrier_graph_storage_limits(), max_work: 10000, },
    10000L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("the original keyed Graph construction must complete")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(schema)) else {
    fail("the original Graph identity contract must remain available")
  }
  let domain = @carrier_contract.graph_domain(
    @carrier_contract.graph_definition(schema),
  )
  let receiver = keyed_graph_receiver(
    owner,
    body="[{\"from\":\"g\",\"degree\":{\"direction\":\"out\"}}]",
  )
  let input = @graphs.prepare_producer_read(receiver, 0, owner, graph).unwrap()
  let start = fn(max_rows) {
    @local_sga.start_graph_degree(
      @bounded.control(),
      task_test_completion(receiver),
      prepared_sequence(receiver),
      0,
      input,
      max_rows,
      {
        max_work: 100000,
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 50,
      },
      10,
      10000,
      10000,
      [],
    ).unwrap()
  }
  let active = start(2)
  let mut output = None
  for _ in 0..<10000 {
    match @local_sga.advance_graph_degree(active, 1).unwrap() {
      @local_sga.GraphDegreeContinue(work~, ..) => assert_true(work > 0L)
      @local_sga.GraphDegreeComplete(rows, ..) => {
        output = Some(rows)
        break
      }
      _ => fail("degree execution must preserve the checked node_id output")
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  // Parallel keyed edges a->b contribute two outgoing incidences to a and
  // none to b. Expected counts come from those input records, not the kernel.
  for index, (key, degree) in [("a", "2"), ("b", "0")] {
    assert_eq(
      @execution.completed_output_row_wire(output, index, 10000, 10000, 50).unwrap(),
      "{\"degree\":" +
      degree +
      ",\"node_id\":{\"$json\":{\"definition\":\"N\",\"domain\":\"" +
      domain +
      "\",\"key\":[\"" +
      key +
      "\"],\"key_types\":[{\"kind\":\"string\"}]}}}",
    )
  }
  assert_true(@local_sga.cleanup_graph_degree(active).unwrap())
  assert_false(@local_sga.cleanup_graph_degree(active).unwrap())
  let short = start(1)
  let mut refused = false
  for _ in 0..<10000 {
    match @local_sga.advance_graph_degree(short, 1).unwrap() {
      @local_sga.GraphDegreeContinue(..) => ()
      @local_sga.GraphDegreeFailed(
        @local_sga.GraphBoundsOutput(@execution.CaptureLimit),
        ..
      ) => {
        refused = true
        break
      }
      _ =>
        fail(
          "one-short degree output must fail without a completed partial result",
        )
    }
  }
  assert_true(refused)
  assert_true(@local_sga.cleanup_graph_degree(short).unwrap())
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
