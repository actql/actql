///|
fn graph_selector_relation() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("key"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=3,
    ).unwrap(),
  )
}

///|
fn graph_subgraph_owner(
  source : String,
  with_relation : Bool,
) -> @lowering_relation.BoundPrepared {
  let inputs = if with_relation {
    [("g", graph_match_carrier()), ("selected", graph_selector_relation())]
  } else {
    [("g", graph_match_carrier())]
  }
  let checked = @pipeline.check_carriers(cursor(source), inputs, None, None, {
    max_steps: 100,
    max_work: 100000,
    max_text_bytes: 100000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 4000,
  }).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn graph_subgraph_wire(source : String, with_relation : Bool) -> String raise {
  let sequence = @lowering_relation.prepare_sequence(
    graph_subgraph_owner(source, with_relation),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  @encode.finish(writer)
}

///|
test "Graph subgraph retains explicit node and edge predicates" {
  assert_eq(
    graph_subgraph_wire(
      "[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"where\":\"active\"},\"edges\":\"active\"}}]",
      false,
    ),
    "[{\"id\":\"subgraph_0\",\"in\":[\"input_0\"],\"op\":\"SGA.subgraph\",\"params\":{\"nodes\":{\"where\":{\"body\":\"active\",\"op\":\"field\"}},\"edges\":{\"body\":\"active\",\"op\":\"field\"}}}]",
  )
}

///|
test "Graph subgraph retains the exact relation selector edge" {
  assert_eq(
    graph_subgraph_wire(
      "[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"from\":\"selected\",\"id\":\"key\"}}}]",
      true,
    ),
    "[{\"id\":\"subgraph_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.subgraph\",\"params\":{\"nodes\":{\"input_port\":1,\"id\":\"key\"},\"edges\":{\"body\":true,\"op\":\"literal\"}}}]",
  )
}

///|
test "Graph subgraph relation selector has exact preparation bounds" {
  let owner = graph_subgraph_owner(
    "[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"from\":\"selected\",\"id\":\"key\"}}}]",
    true,
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 1,
      max_name_bytes: 3,
    })
    is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 1,
      max_name_bytes: 2,
    })
    is Err(
      @lowering_relation.GraphSubgraphFailure(
        0,
        @lowering_relation.GraphSubgraphPreparationLimit
      )
    ),
  )
}
