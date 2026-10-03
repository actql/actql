///|
test "current TRAIL retains homogeneous bounds edge labels and independent identities" {
  let id = graph_match_identity(2)
  let source = "[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
    id +
    "]},\"direction\":\"out\",\"edge_types\":[\"owns\"],\"min_hops\":1,\"max_hops\":3,\"path_mode\":\"trail\",\"emit\":\"paths\",\"max_output_rows\":10}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_current_owner(source, false),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"traverse_0\",\"in\":[\"input_0\"],\"op\":\"SGA.traverse\",\"params\":{\"start\":{\"ids\":[" +
    id +
    "]},\"path_mode\":\"trail\",\"direction\":\"out\",\"edge_types\":[\"owns\"],\"min_hops\":1,\"max_hops\":3,\"emit\":\"paths\",\"max_output_rows\":10}}]",
  )
}

///|
test "current TRAIL exposes a complete homogeneous kernel view and keyed path schema" {
  let id = graph_match_identity(2)
  let source = "[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
    id +
    "," +
    id +
    "]},\"direction\":\"out\",\"edge_types\":[\"owns\",\"owns\"],\"min_hops\":1,\"max_hops\":3,\"path_mode\":\"trail\",\"emit\":\"paths\",\"max_output_rows\":10}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_current_owner(source, false),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphTraverseStep(view)) else {
    fail("prepared TRAIL")
  }
  assert_eq(
    @lowering_relation.graph_traverse_property_path_mode(view),
    @graph.Trail,
  )
  assert_false(@lowering_relation.graph_traverse_patterned(view))
  assert_true(@lowering_relation.graph_traverse_emits_paths(view))
  assert_eq(@lowering_relation.graph_traverse_bounds(view), Some((1L, 3L)))
  assert_eq(@lowering_relation.graph_traverse_output_guard(view), Some(10L))
  assert_eq(@lowering_relation.graph_traverse_start_id_count(view), 2)
  assert_eq(
    graph_match_checked_value_wire(
      @lowering_relation.graph_traverse_start_id_at(view, 0).unwrap(),
    ),
    id,
  )
  assert_eq(
    graph_match_checked_value_wire(
      @lowering_relation.graph_traverse_start_id_at(view, 1).unwrap(),
    ),
    id,
  )
  assert_eq(@lowering_relation.graph_traverse_start_relation_field(view), None)
  assert_eq(@lowering_relation.graph_traverse_hop_count(view), 1)
  assert_eq(
    @lowering_relation.graph_traverse_hop_direction(view, 0),
    Some(@graph.Outgoing),
  )
  assert_eq(@lowering_relation.graph_traverse_hop_type_count(view, 0), Some(2))
  assert_eq(
    @lowering_relation.graph_traverse_hop_type_at(view, 0, 1),
    Some("owns"),
  )
  let schema = @lowering_relation.graph_traverse_output_schema(view)
  assert_eq(@schema.field_count(schema), 5)
  for field in ["node_ids", "edge_ids"] {
    guard @schema.lookup(schema, @schema.Unqualified(field)) is Some(contract) &&
      contract.shape is @contract.Array(element, ..) else {
      fail("keyed identity array")
    }
    assert_true(element.shape is @contract.Json)
    assert_false(element.nullable)
  }
}

///|
test "current TRAIL retains patterned label selection and the exact Relation selector port" {
  let source = "[{\"from\":\"g\",\"traverse\":{\"start\":{\"from\":\"selected\",\"id\":\"key\"},\"hops\":[{\"direction\":\"both\",\"edge_types\":[\"owns\"]}],\"path_mode\":\"trail\",\"emit\":\"paths\"}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_current_owner(source, true),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(30000, 3000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"traverse_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.traverse\",\"params\":{\"start\":{\"input_port\":1,\"id\":\"key\"},\"path_mode\":\"trail\",\"hops\":[{\"direction\":\"both\",\"edge_types\":[\"owns\"]}],\"emit\":\"paths\"}}]",
  )
}

///|
test "current TRAIL exposes a patterned keyed selector and checks predicate scope" {
  let source = "[{\"from\":\"g\",\"traverse\":{\"start\":{\"from\":\"selected\",\"id\":\"key\"},\"hops\":[{\"direction\":\"both\",\"edge_types\":[\"owns\"]}],\"path_mode\":\"trail\",\"emit\":\"paths\"}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_current_owner(source, true),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphTraverseStep(view)) else {
    fail("prepared TRAIL")
  }
  assert_true(@lowering_relation.graph_traverse_patterned(view))
  assert_true(@lowering_relation.graph_traverse_emits_paths(view))
  assert_eq(@lowering_relation.graph_traverse_bounds(view), None)
  assert_eq(
    @lowering_relation.graph_traverse_property_path_mode(view),
    @graph.Trail,
  )
  assert_eq(
    @lowering_relation.graph_traverse_start_relation_field(view),
    Some(@schema.Unqualified("key")),
  )
  assert_eq(
    @lowering_relation.graph_traverse_hop_direction(view, 0),
    Some(@graph.Both),
  )
  assert_eq(
    @schema.field_count(@lowering_relation.graph_traverse_output_schema(view)),
    5,
  )
  let accepted = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
      graph_match_identity(2) +
      "]},\"hops\":[{\"direction\":\"both\",\"node_where\":\"active\"}],\"path_mode\":\"trail\",\"emit\":\"paths\"}}]",
    ),
    [("g", graph_match_carrier())],
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
  )
  assert_true(accepted is Ok(_))
}

///|
test "current TRAIL prepares label and selector names under exact entry and name limits" {
  let source = "[{\"from\":\"g\",\"traverse\":{\"start\":{\"from\":\"selected\",\"id\":\"key\"},\"direction\":\"out\",\"edge_types\":[\"owns\"],\"min_hops\":0,\"max_hops\":1,\"path_mode\":\"trail\",\"emit\":\"paths\"}}]"
  let owner = graph_current_owner(source, true)
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 3,
      max_name_bytes: 7,
    })
    is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 3,
      max_name_bytes: 6,
    })
    is Err(
      @lowering_relation.GraphTraverseFailure(
        0,
        @lowering_relation.GraphTraversePreparationLimit
      )
    ),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 2,
      max_name_bytes: 7,
    })
    is Err(
      @lowering_relation.GraphTraverseFailure(
        0,
        @lowering_relation.GraphTraversePreparationLimit
      )
    ),
  )
}
