///|
fn carrier_projection_owner(
  source : String,
  inputs : Array[(String, @carrier.Carrier)],
) -> @lowering_relation.BoundPrepared {
  let checked = @pipeline.check_carriers(cursor(source), inputs, None, None, {
    max_steps: 10,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "all Carrier projections retain their registered typed operation" {
  let graph = carrier_projection_owner(
    "[{\"from\":\"g\",\"node_rows\":true},{\"from\":\"g\",\"edge_rows\":true}]",
    [("g", graph_match_carrier())],
  )
  let graph_sequence = @lowering_relation.prepare_sequence(
    graph,
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(graph_sequence, 0)
    is Some(@lowering_relation.CarrierProjectionStep(nodes)) &&
    @lowering_relation.sequence_step(graph_sequence, 1)
    is Some(@lowering_relation.CarrierProjectionStep(edges)) else {
    fail("expected graph projections")
  }
  assert_eq(
    @lowering_relation.carrier_projection_operation(nodes),
    @projection.NodeRows,
  )
  assert_eq(
    @lowering_relation.carrier_projection_operation(edges),
    @projection.EdgeRows,
  )

  let vectors = carrier_projection_owner(
    "[{\"from\":\"rows\",\"to_vectors\":{\"id\":\"product_id\",\"vector\":\"embedding\"}},{\"vectors\":true}]",
    [("rows", vector_relation())],
  )
  let vector_sequence = @lowering_relation.prepare_sequence(
    vectors,
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(vector_sequence, 1)
    is Some(@lowering_relation.CarrierProjectionStep(projected)) else {
    fail("expected vector projection")
  }
  assert_eq(
    @lowering_relation.carrier_projection_operation(projected),
    @projection.Vectors,
  )
}
