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
test "Vectors projection retains its registered typed operation" {
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

///|
test "Graph row projections lower to registered typed Carrier bridges" {
  for operation in ["node_rows", "edge_rows"] {
    let owner = carrier_projection_owner(
      "[{\"from\":\"g\",\"" + operation + "\":true}]",
      [("g", graph_match_carrier())],
    )
    let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
    guard @lowering_relation.sequence_step(sequence, 0)
      is Some(@lowering_relation.CarrierProjectionStep(checked)) else {
      fail("typed Graph bridge")
    }
    assert_eq(
      @lowering_relation.carrier_projection_operation(checked),
      if operation == "node_rows" {
        @projection.NodeRows
      } else {
        @projection.EdgeRows
      },
    )
    let node = @lowering_relation.node_at(
      @lowering_relation.bound_preparation(owner),
      0,
    ).unwrap()
    assert_true(@lowering_relation.node_accepts_managed_carrier_view(node, 0))
    assert_false(@lowering_relation.node_accepts_managed_carrier_view(node, 1))
    assert_true(
      @lowering_relation.node_supports_selected_managed_execution(node),
    )
    assert_eq(
      @lowering_relation.operation(node),
      if operation == "node_rows" {
        "BRIDGE.graph.to_node_rows"
      } else {
        "BRIDGE.graph.to_edge_rows"
      },
    )
  }
}
