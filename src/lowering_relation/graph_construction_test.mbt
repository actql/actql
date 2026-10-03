///|
fn keyed_lowering_constructor_checked(
  shared_endpoint? : Bool = false,
) -> @pipeline.CheckedPipeline {
  let source =
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false},"weight":{"type":"number","nullable":false}},"rows":[{"id":1,"src":1,"dst":1,"weight":2}]},"as":"rows"}
  let source_key = if shared_endpoint { "id" } else { "src" }
  let target_key = if shared_endpoint { "id" } else { "dst" }
  @pipeline.check_carriers(
    cursor(
      "[" +
      source +
      ",{" +
      "\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\"," +
      "\"nodes\":[{\"name\":\"N\",\"from\":\"rows\",\"key\":[\"id\"],\"labels\":[{\"name\":\"Node\",\"properties\":{\"mode\":\"no_properties\"}}]}]," +
      "\"edges\":[{\"name\":\"E\",\"from\":\"rows\",\"key\":[\"id\"],\"labels\":[{\"name\":\"owns\",\"properties\":{\"mode\":\"columns\",\"columns\":[{\"from\":\"weight\",\"to\":\"weight\"}]}}]," +
      "\"source\":{\"definition\":\"N\",\"key\":[\"" +
      source_key +
      "\"]}," +
      "\"target\":{\"definition\":\"N\",\"key\":[\"" +
      target_key +
      "\"]}}]},\"as\":\"g\"}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 4000,
    },
  ).unwrap()
}

///|
fn keyed_lowering_constructor_owner(
  shared_endpoint? : Bool = false,
) -> @lowering_relation.BoundPrepared {
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(
      keyed_lowering_constructor_checked(shared_endpoint~),
      limits(),
    ).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "keyed constructor retains distinct repeated producer roles and independent edge key" {
  let sequence = @lowering_relation.prepare_sequence(
    keyed_lowering_constructor_owner(),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.PropertyGraphConstructionStep(graph)) else {
    fail("current constructor required")
  }
  assert_eq(@lowering_relation.property_graph_construction_node_count(graph), 1)
  assert_eq(@lowering_relation.property_graph_construction_edge_count(graph), 1)
  let node = @lowering_relation.property_graph_construction_node_at(graph, 0).unwrap()
  let edge = @lowering_relation.property_graph_construction_edge_at(graph, 0).unwrap()
  let element = @lowering_relation.property_edge_binding_element(edge)
  // Producer schema is ordered dst, id, src, weight. Both roles use the same
  // producer, but the independent edge key is not its endpoint tuple.
  assert_eq(@lowering_relation.property_binding_input(node), 0)
  assert_eq(@lowering_relation.property_binding_input(element), 1)
  assert_eq(@lowering_relation.property_binding_keys(node), [1])
  assert_eq(@lowering_relation.property_binding_keys(element), [1])
  assert_eq(@lowering_relation.property_binding_properties(element), [3])
  assert_eq(@lowering_relation.property_edge_binding_keys(edge), ([2], [0]))
  let checked = @lowering_relation.property_graph_construction_checked(graph)
  assert_eq(@graph.property_construction_node_count(checked), 1)
  assert_eq(@graph.property_construction_edge_count(checked), 1)
}

///|
test "keyed constructor uses one canonical bridge without tuple expansion" {
  let sequence = @lowering_relation.prepare_sequence(
    keyed_lowering_constructor_owner(),
    sequence_limits(),
  ).unwrap()
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 1),
    Some(1),
  )
  assert_eq(
    @lowering_relation.sequence_canonical_node_at(sequence, 1, 0).unwrap().operation,
    "BRIDGE.rows.to_property_graph",
  )
  let writer = @encode.writer(30000, 3000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  let wire = @encode.finish(writer)
  assert_true(
    wire.contains(
      "\"in\":[\"values_0\",\"values_0\"],\"op\":\"BRIDGE.rows.to_property_graph\"",
    ),
  )
  assert_true(
    wire.contains(
      "\"element\":{\"definition\":\"E\",\"input\":1,\"keys\":[1],\"properties\":[3]},\"source\":[2],\"target\":[0]",
    ),
  )
  assert_true(
    wire.contains(
      "\"nodes\":[{\"definition\":\"N\",\"input\":0,\"keys\":[1],\"properties\":[]}]",
    ),
  )
  assert_false(wire.contains("BRIDGE.rows.to_graph\""))
  assert_false(wire.contains("REL.join"))
  assert_false(wire.contains("REL.distinct"))
}

///|
test "keyed constructor preparation keeps exact finite shared limits" {
  let checked = keyed_lowering_constructor_checked()
  let prepared = @lowering_relation.prepare(checked, limits()).unwrap()
  let usage = @lowering_relation.usage(prepared)
  let exact : @lowering_relation.Limits = {
    max_nodes: usage.nodes,
    max_references: usage.references,
    max_work: usage.work,
    max_identifier_bytes: usage.identifier_bytes,
  }
  assert_true(@lowering_relation.prepare(checked, exact) is Ok(_))
  for
    limited in [
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_references: exact.max_references - 1, },
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_identifier_bytes: exact.max_identifier_bytes - 1, },
    ] {
    assert_true(@lowering_relation.prepare(checked, limited) is Err(_))
  }
  let owner = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  assert_true(
    @lowering_relation.prepare_sequence(owner, sequence_limits()) is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_steps: 1,
    })
    is Err(@lowering_relation.SequenceLimit),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 0,
    })
    is Err(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_name_bytes: 0,
    })
    is Err(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      expressions: { ..expression_limits(), max_work: 0, },
    })
    is Err(_),
  )
}

///|
test "retired endpoint-derived constructor cannot synthesize a current Graph" {
  let rows = @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("src_id"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          @schema.Unqualified("dst_id"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=12,
    ).unwrap(),
  )
  let issue = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"rows\",\"graph\":{\"source\":\"src_id\",\"target\":\"dst_id\"},\"as\":\"g\"}]",
    ),
    [("rows", rows)],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap_err()
  assert_true(issue.kind is @pipeline.Graph(@graph.UnsupportedGraphOperation))
  assert_true(issue.path.contains(@source.Key("graph")))
}

///|
test "shared keyed endpoint retains both roles without projecting or merging edge identity" {
  let sequence = @lowering_relation.prepare_sequence(
    keyed_lowering_constructor_owner(shared_endpoint=true),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.PropertyGraphConstructionStep(graph)) else {
    fail("current constructor required")
  }
  let edge = @lowering_relation.property_graph_construction_edge_at(graph, 0).unwrap()
  assert_eq(@lowering_relation.property_edge_binding_keys(edge), ([1], [1]))
  assert_eq(
    @lowering_relation.property_binding_keys(
      @lowering_relation.property_edge_binding_element(edge),
    ),
    [1],
  )
  let copy = @lowering_relation.property_edge_binding_keys(edge)
  copy.0[0] = 99
  assert_eq(@lowering_relation.property_edge_binding_keys(edge), ([1], [1]))
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 1),
    Some(1),
  )
}
