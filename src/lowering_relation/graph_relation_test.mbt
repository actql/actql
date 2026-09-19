///|
fn graph_relation_owner(source : String) -> @lowering_relation.BoundPrepared {
  let graph = graph_union_carrier()
  let checked = @pipeline.check_carriers(
    cursor(source),
    [("a", graph), ("b", graph)],
    None,
    None,
    {
      max_steps: 100,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 4000,
    },
  ).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn graph_relation_wire(source : String) -> String raise {
  let sequence = @lowering_relation.prepare_sequence(
    graph_relation_owner(source),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  @encode.finish(writer)
}

///|
test "Graph equality and diff retain exact binary edges" {
  assert_eq(
    graph_relation_wire("[{\"from\":\"a\",\"graphs_equal\":{\"with\":\"b\"}}]"),
    "[{\"id\":\"graphs_equal_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.equal\",\"params\":{}}]",
  )
  assert_eq(
    graph_relation_wire("[{\"from\":\"a\",\"graph_diff\":{\"with\":\"b\"}}]"),
    "[{\"id\":\"graph_diff_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.diff\",\"params\":{}}]",
  )
}

///|
test "Graph delta application retains produced delta field and budgets" {
  let source = "[{\"from\":\"a\",\"graph_diff\":{\"with\":\"b\"},\"as\":\"changes\"},{\"from\":\"a\",\"apply_graph_delta\":{\"with\":\"changes\",\"field\":\"delta\"}}]"
  assert_eq(
    graph_relation_wire(source),
    "[{\"id\":\"graph_diff_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.diff\",\"params\":{}},{\"id\":\"apply_graph_delta_1\",\"in\":[\"input_0\",\"graph_diff_0\"],\"op\":\"SGA.apply_delta\",\"params\":{\"field\":\"delta\"}}]",
  )
  assert_true(
    @lowering_relation.prepare_sequence(graph_relation_owner(source), {
      ..sequence_limits(),
      max_name_bytes: 4,
    })
    is Err(
      @lowering_relation.GraphRelationFailure(
        1,
        @lowering_relation.GraphRelationPreparationLimit
      )
    ),
  )
}
