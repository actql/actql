///|
fn subgraph_owner(
  producer : @lower.BoundPrepared,
  ids : String,
  edge_predicate? : String? = None,
) -> @lower.BoundPrepared {
  let edge = match edge_predicate {
    Some(predicate) => ",\"edges\":\"" + predicate + "\""
    None => ""
  }
  bind(
    @pipeline.check_with_evidence(
      cursor("[{\"subgraph\":{\"nodes\":{\"ids\":" + ids + "}" + edge + "}}]"),
      [
        (
          "prior",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(producer)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(cursor("\"prior\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn subgraph_source_graph(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
) -> @graph.Completed {
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    4096L,
    fn() { live.val },
  ).unwrap()
  @graph.append_node(output, number(1.0), [text("a")]).unwrap()
  @graph.append_node(output, number(2.0), [text("b")]).unwrap()
  @graph.append_node(output, number(3.0), [text("c")]).unwrap()
  @graph.append_edge(
    output,
    number(1.0),
    number(2.0),
    Some(text("kept", nullable=true)),
    [number(12.0)],
  ).unwrap()
  @graph.append_edge(
    output,
    number(2.0),
    number(3.0),
    Some(text("removed", nullable=true)),
    [number(23.0)],
  ).unwrap()
  @graph.finish_output(output).unwrap()
}

///|
test "subgraph selects literal nodes and induced edges in bounded steps" {
  let producer = source_owner()
  let source_live = Ref(true)
  let source = subgraph_source_graph(producer, source_live)
  let owner = subgraph_owner(producer, "[2,1,2]")
  let input = @graph.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_subgraph(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_eq(subgraph_max_noninterruptible_value_nodes(execution), 401)
  let mut output : @graph.Completed? = None
  let mut polls = 0
  while output is None {
    match advance_subgraph(execution, 1).unwrap() {
      SubgraphContinue(_) => polls += 1
      SubgraphComplete(value, ..) => output = Some(value)
      SubgraphFailed(_, ..) => fail("subgraph failed")
      SubgraphStopped(_, ..) => fail("subgraph stopped")
    }
  }
  assert_true(polls > 1)
  assert_eq(cleanup_subgraph(execution), Ok(true))
  source_live.val = false
  guard output is Some(completed) else { fail("completed subgraph") }
  guard @graph.completed_storage(completed) is Some(material) else {
    fail("retained subgraph storage")
  }
  assert_eq(@storage.node_count(material), 2)
  assert_eq(@storage.edge_count(material), 1)
  assert_true(
    @value.compare_key_values(
      @storage.node_identity(material, 0).unwrap(),
      number(1.0),
    )
    is Ok(0),
  )
  assert_true(
    @value.compare_key_values(
      @storage.node_identity(material, 1).unwrap(),
      number(2.0),
    )
    is Ok(0),
  )
  assert_eq(@storage.edge_endpoints(material, 0), Some((0, 1)))
}

///|
test "subgraph cancellation reclaims unpublished output" {
  let producer = source_owner()
  let source = subgraph_source_graph(producer, Ref(true))
  let owner = subgraph_owner(producer, "[1,2]")
  let input = @graph.prepare_producer_read(owner, 0, producer, source).unwrap()
  let control = @bounded.control()
  let execution = start_subgraph(
    control,
    sequence(owner),
    0,
    input,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_subgraph(execution, 1).unwrap() is SubgraphContinue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_subgraph(execution, 1).unwrap()
    is SubgraphStopped(@bounded.Cancelled, ..),
  )
  assert_true(subgraph_cleanup_pending(execution))
  assert_eq(cleanup_subgraph(execution), Ok(true))
  assert_false(subgraph_cleanup_pending(execution))
}

///|
test "subgraph preserves a literal false edge predicate" {
  let producer = source_owner()
  let source = subgraph_source_graph(producer, Ref(true))
  let owner = subgraph_owner(producer, "[1,2]", edge_predicate=Some("false"))
  let input = @graph.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_subgraph(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut output : @graph.Completed? = None
  while output is None {
    match advance_subgraph(execution, 1).unwrap() {
      SubgraphContinue(_) => ()
      SubgraphComplete(value, ..) => output = Some(value)
      _ => fail("literal edge predicate failed")
    }
  }
  assert_eq(cleanup_subgraph(execution), Ok(true))
  guard output is Some(completed) &&
    @graph.completed_storage(completed) is Some(material) else {
    fail("completed literal predicate subgraph")
  }
  assert_eq(@storage.node_count(material), 2)
  assert_eq(@storage.edge_count(material), 0)
}
