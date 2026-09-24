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
fn subgraph_predicate_owner(
  producer : @lower.BoundPrepared,
  nodes : String,
  edges : String,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"subgraph\":{\"nodes\":" + nodes + ",\"edges\":\"" + edges + "\"}}]",
      ),
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
    None,
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
    None,
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
test "subgraph admits exact combined selector and output workspace" {
  let producer = source_owner()
  let source = subgraph_source_graph(producer, Ref(true))
  let owner = subgraph_owner(producer, "[1,2]")
  let input = @graph.prepare_producer_read(owner, 0, producer, source).unwrap()
  // Three selection flags and two pairs of selector slots coexist with two
  // five-slot nodes and one eight-slot labeled edge in the output builder.
  let execution = start_subgraph(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    None,
    { ..storage_limits(), max_workspace_slots: 25, },
    4096L,
    fn() { true },
  ).unwrap()
  let mut output : @graph.Completed? = None
  for _ in 0..<64 {
    if output is None {
      match advance_subgraph(execution, 1).unwrap() {
        SubgraphContinue(_) => ()
        SubgraphComplete(value, ..) => output = Some(value)
        SubgraphFailed(_, ..) =>
          fail("exact selector and output workspace did not complete")
        SubgraphStopped(_, ..) => fail("exact selector workspace stopped")
      }
    }
  }
  assert_true(output is Some(_))
  assert_eq(cleanup_subgraph(execution), Ok(true))
}

///|
test "subgraph rejects one short combined selector and output workspace" {
  let producer = source_owner()
  let source = subgraph_source_graph(producer, Ref(true))
  let owner = subgraph_owner(producer, "[1,2]")
  let input = @graph.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_subgraph(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    None,
    { ..storage_limits(), max_workspace_slots: 24, },
    4096L,
    fn() { true },
  ).unwrap()
  let mut failed = false
  for _ in 0..<64 {
    if !failed {
      match advance_subgraph(execution, 1).unwrap() {
        SubgraphContinue(_) => ()
        SubgraphFailed(
          SubgraphOutput(@graph.Storage(@storage.WorkspaceLimit)),
          ..
        ) => failed = true
        SubgraphComplete(_, ..)
        | SubgraphFailed(_, ..)
        | SubgraphStopped(_, ..) =>
          fail("one-short combined workspace was not enforced")
      }
    }
  }
  assert_true(failed)
  assert_true(subgraph_cleanup_pending(execution))
  assert_eq(cleanup_subgraph(execution), Ok(true))
}

///|
test "subgraph admits exact literal-selection control work" {
  let producer = source_owner()
  let source = subgraph_source_graph(producer, Ref(true))
  let owner = subgraph_owner(producer, "[1,2]")
  // Three selection flags, two selector reads, six identity comparisons,
  // two selector checks, three node copies, two edge checks, and one finish
  // require exactly 19 control steps, independent of output-value work.
  for (work, accepted) in [(19, true), (18, false)] {
    let input = @graph.prepare_producer_read(owner, 0, producer, source).unwrap()
    let execution = start_subgraph(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      None,
      storage_limits(),
      4096L,
      fn() { true },
      control_work_limit=Some(work),
    ).unwrap()
    let mut terminal = false
    let mut charged = 0L
    for _ in 0..<64 {
      if !terminal {
        match advance_subgraph(execution, 1).unwrap() {
          SubgraphContinue(work=delta, ..) => {
            assert_true(delta >= charged && delta - charged <= 1L)
            charged = delta
          }
          SubgraphComplete(output, work=delta, ..) => {
            assert_true(delta >= charged && delta - charged <= 1L)
            charged = delta
            assert_true(accepted)
            assert_true(@graph.completed_storage(output) is Some(_))
            terminal = true
          }
          SubgraphFailed(SubgraphWorkLimit, work=delta, ..) => {
            assert_true(delta >= charged && delta - charged <= 1L)
            charged = delta
            assert_false(accepted)
            assert_true(subgraph_cleanup_pending(execution))
            terminal = true
          }
          _ => fail("unexpected literal subgraph work result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(charged, work.to_int64())
    assert_eq(cleanup_subgraph(execution), Ok(true))
    assert_true(@graph.producer_read_available(input))
  }
}

///|
test "subgraph rejects every missing identity before materialization" {
  let producer = source_owner()
  let source = subgraph_source_graph(producer, Ref(true))
  for (ids, missing) in [("[1,4]", 1), ("[4,1]", 0), ("[4]", 0)] {
    let owner = subgraph_owner(producer, ids)
    let execution = start_subgraph(
      @bounded.control(),
      sequence(owner),
      0,
      @graph.prepare_producer_read(owner, 0, producer, source).unwrap(),
      None,
      storage_limits(),
      4096L,
      fn() { true },
    ).unwrap()
    let mut failed = false
    while !failed {
      match advance_subgraph(execution, 1).unwrap() {
        SubgraphContinue(_) => ()
        SubgraphFailed(MissingSubgraphNodeIdentity(index), progress=0L, ..) => {
          assert_eq(index, missing)
          failed = true
        }
        _ => fail("missing subgraph identity was accepted")
      }
    }
    assert_eq(cleanup_subgraph(execution), Ok(true))
  }

  let owner = subgraph_owner(producer, "[1,4]", edge_predicate=Some("false"))
  let execution = start_subgraph(
    @bounded.control(),
    sequence(owner),
    0,
    @graph.prepare_producer_read(owner, 0, producer, source).unwrap(),
    None,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut failed = false
  while !failed {
    match advance_subgraph(execution, 1).unwrap() {
      SubgraphContinue(_) => ()
      SubgraphFailed(MissingSubgraphNodeIdentity(1), progress=0L, ..) =>
        failed = true
      _ => fail("false edge predicate hid a missing identity")
    }
  }
  assert_eq(cleanup_subgraph(execution), Ok(true))

  let empty_output = @graph.prepare_output(
    producer,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let empty = @graph.finish_output(empty_output).unwrap()
  let empty_owner = subgraph_owner(producer, "[1]")
  let empty_execution = start_subgraph(
    @bounded.control(),
    sequence(empty_owner),
    0,
    @graph.prepare_producer_read(empty_owner, 0, producer, empty).unwrap(),
    None,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut empty_failed = false
  while !empty_failed {
    match advance_subgraph(empty_execution, 1).unwrap() {
      SubgraphContinue(_) => ()
      SubgraphFailed(MissingSubgraphNodeIdentity(0), progress=0L, ..) =>
        empty_failed = true
      _ => fail("empty graph accepted a missing identity")
    }
  }
  assert_eq(cleanup_subgraph(empty_execution), Ok(true))
}

///|
test "subgraph materializes derived endpoints as declared selected nodes" {
  let producer = empty_graph_owner()
  let source_output = @graph.prepare_output(
    producer,
    @pipeline.Step(0),
    @storage.DerivedEndpoints,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  @graph.append_edge(
    source_output,
    number(1.0),
    number(2.0),
    Some(text("edge", nullable=true)),
    [],
  ).unwrap()
  let source = @graph.finish_output(source_output).unwrap()
  let owner = subgraph_owner(producer, "[1]")
  let execution = start_subgraph(
    @bounded.control(),
    sequence(owner),
    0,
    @graph.prepare_producer_read(owner, 0, producer, source).unwrap(),
    None,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut output : @graph.Completed? = None
  while output is None {
    match advance_subgraph(execution, 1).unwrap() {
      SubgraphContinue(_) => ()
      SubgraphComplete(value, ..) => output = Some(value)
      _ => fail("derived-endpoint subgraph failed")
    }
  }
  assert_eq(cleanup_subgraph(execution), Ok(true))
  guard output is Some(completed) &&
    @graph.completed_storage(completed) is Some(material) else {
    fail("completed derived-endpoint subgraph")
  }
  assert_eq(@storage.mode(material), @storage.DeclaredNodes)
  assert_eq(@storage.node_count(material), 1)
  assert_eq(@storage.edge_count(material), 0)
  assert_true(@storage.node_index(material, number(1.0)).unwrap() is Some(_))
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
    None,
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

///|
test "subgraph evaluates node and edge predicates" {
  let producer = source_owner()
  let source = subgraph_source_graph(producer, Ref(true))
  let node_owner = subgraph_predicate_owner(
    producer, "{\"where\":\"name = 'a' or name = 'b'\"}", "true",
  )
  let node_execution = start_subgraph(
    @bounded.control(),
    sequence(node_owner),
    0,
    @graph.prepare_producer_read(node_owner, 0, producer, source).unwrap(),
    None,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut node_output : @graph.Completed? = None
  while node_output is None {
    match advance_subgraph(node_execution, 1).unwrap() {
      SubgraphContinue(_) => ()
      SubgraphComplete(value, ..) => node_output = Some(value)
      _ => fail("node predicate subgraph failed")
    }
  }
  assert_eq(cleanup_subgraph(node_execution), Ok(true))
  guard node_output is Some(node_completed) &&
    @graph.completed_storage(node_completed) is Some(node_material) else {
    fail("completed node predicate subgraph")
  }
  assert_eq(@storage.node_count(node_material), 2)
  assert_eq(@storage.edge_count(node_material), 1)

  let edge_owner = subgraph_predicate_owner(
    producer, "{\"ids\":[1,2,3]}", "weight > 20",
  )
  let edge_execution = start_subgraph(
    @bounded.control(),
    sequence(edge_owner),
    0,
    @graph.prepare_producer_read(edge_owner, 0, producer, source).unwrap(),
    None,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut edge_output : @graph.Completed? = None
  while edge_output is None {
    match advance_subgraph(edge_execution, 1).unwrap() {
      SubgraphContinue(_) => ()
      SubgraphComplete(value, ..) => edge_output = Some(value)
      _ => fail("edge predicate subgraph failed")
    }
  }
  assert_eq(cleanup_subgraph(edge_execution), Ok(true))
  guard edge_output is Some(edge_completed) &&
    @graph.completed_storage(edge_completed) is Some(edge_material) else {
    fail("completed edge predicate subgraph")
  }
  assert_eq(@storage.node_count(edge_material), 3)
  assert_eq(@storage.edge_count(edge_material), 1)
  assert_eq(@storage.edge_endpoints(edge_material, 0), Some((1, 2)))
}
