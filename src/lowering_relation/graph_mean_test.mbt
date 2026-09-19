///|
fn graph_mean_owner(
  body : String,
  graph : @carrier.Carrier,
) -> @lowering_relation.BoundPrepared {
  let checked = @pipeline.check_carriers(
    cursor("[{\"mean_graphs\":" + body + ",\"as\":\"m\"}]"),
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
fn graph_mean_wire(body : String, graph : @carrier.Carrier) -> String raise {
  let sequence = @lowering_relation.prepare_sequence(
    graph_mean_owner(body, graph),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  @encode.finish(writer)
}

///|
test "Graph mean lowers one repeated finite-list occurrence" {
  let body = "{\"with\":[\"a\",\"b\",\"a\"],\"weights\":[1,2,3],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{}}}"
  assert_eq(
    graph_mean_wire(body, graph_union_carrier()),
    "[{\"id\":\"mean_graphs_0\",\"in\":[\"input_0\",\"input_1\",\"input_0\"],\"op\":\"SGA.mean_structural\",\"params\":{\"weights\":[1,2,3],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{}}}}]",
  )
  let constrained = { ..sequence_limits(), max_bindings: 2, }
  assert_true(
    @lowering_relation.prepare_sequence(
      graph_mean_owner(body, graph_union_carrier()),
      constrained,
    )
    is Err(
      @lowering_relation.GraphMeanFailure(
        0,
        @lowering_relation.GraphMeanPreparationLimit
      )
    ),
  )
}

///|
test "Graph mean emits checked property policies" {
  let body = "{\"with\":[\"a\",\"b\"],\"weights\":[1,2],\"support\":{\"nodes\":0.5,\"edges\":1},\"properties\":{\"nodes\":{\"score\":{\"mean\":{\"missing\":\"zero\",\"nulls\":\"exclude\"}}},\"edges\":{\"score\":\"exact_equal\"}}}"
  assert_eq(
    graph_mean_wire(body, graph_union_property_carrier()),
    "[{\"id\":\"mean_graphs_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.mean_structural\",\"params\":{\"weights\":[1,2],\"support\":{\"nodes\":0.5,\"edges\":1},\"properties\":{\"nodes\":{\"score\":{\"mean\":{\"missing\":\"zero\",\"nulls\":\"exclude\"}}},\"edges\":{\"score\":\"exact_equal\"}}}}]",
  )
}
