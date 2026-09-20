///|
fn graph_construction_rows() -> @carrier.Carrier {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  @carrier.relation(
    @carrier.rows(
      [
        (@schema.Unqualified("id"), Some(number)),
        (@schema.Unqualified("src_id"), Some(number)),
        (@schema.Unqualified("dst_id"), Some(number)),
        (@schema.Unqualified("weight"), Some(number)),
      ],
      field_set=@carrier.Closed,
      max_fields=4,
      max_name_bytes=100,
    ).unwrap(),
  )
}

///|
fn explicit_graph_construction_sequence() -> @lowering_relation.PreparedSequence {
  let checked = explicit_graph_construction_checked()
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
}

///|
fn explicit_graph_construction_checked() -> @pipeline.CheckedPipeline {
  @pipeline.check_carriers(
    cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src_id\",\"target\":\"dst_id\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"g\"}]",
    ),
    [("rows", graph_construction_rows())],
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
  ).unwrap()
}

///|
fn self_loop_graph_construction_checked() -> @pipeline.CheckedPipeline {
  @pipeline.check_carriers(
    cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"id\",\"target\":\"id\"," +
      "\"fields\":[]}},\"as\":\"g\"}]",
    ),
    [("rows", graph_construction_rows())],
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
  ).unwrap()
}

///|
test "explicit Graph construction lowers exact repeated input roles" {
  let sequence = explicit_graph_construction_sequence()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphConstructionStep(graph)) else {
    fail("expected Graph construction")
  }
  assert_eq(
    @schema.reference_name(
      @lowering_relation.graph_construction_node_identity(graph),
    ),
    "id",
  )
  assert_eq(
    @schema.reference_name(
      @lowering_relation.graph_construction_edge_source(graph),
    ),
    "src_id",
  )
  assert_eq(
    @schema.reference_name(
      @lowering_relation.graph_construction_edge_target(graph),
    ),
    "dst_id",
  )
  assert_eq(@lowering_relation.graph_construction_node_property_count(graph), 0)
  assert_eq(@lowering_relation.graph_construction_edge_property_count(graph), 1)
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 0),
    Some(5),
  )
  let expected = [
    ("graph_nodes_0", "REL.select"),
    ("graph_edges_0", "REL.select"),
    ("graph_source_closed_0", "REL.join"),
    ("graph_target_closed_0", "REL.join"),
    ("graph_0", "BRIDGE.rows.to_graph"),
  ]
  for index, item in expected {
    assert_eq(
      @lowering_relation.sequence_canonical_node_at(sequence, 0, index).map(occurrence => {
        (occurrence.id, occurrence.operation)
      }),
      Some(item),
    )
  }
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"graph_nodes_0\",\"in\":[\"input_0\"]," +
    "\"op\":\"REL.select\",\"params\":{\"columns\":[" +
    "{\"from\":\"id\",\"to\":\"id\"}]}}," +
    "{\"id\":\"graph_edges_0\",\"in\":[\"input_0\"]," +
    "\"op\":\"REL.select\",\"params\":{\"columns\":[" +
    "{\"from\":\"src_id\",\"to\":\"src_id\"}," +
    "{\"from\":\"dst_id\",\"to\":\"dst_id\"}," +
    "{\"from\":\"weight\",\"to\":\"weight\"}]}}," +
    "{\"id\":\"graph_source_closed_0\",\"in\":[" +
    "\"graph_edges_0\",\"graph_nodes_0\"],\"op\":\"REL.join\"," +
    "\"params\":{\"how\":\"semi\",\"key_pairs\":[{" +
    "\"left\":\"src_id\",\"right\":\"id\"}]," +
    "\"null_key\":\"no_match\",\"on\":{\"left\":{" +
    "\"path\":[\"left\",\"src_id\"],\"type\":\"col\"}," +
    "\"op\":\"eq\",\"right\":{\"path\":[\"right\",\"id\"]," +
    "\"type\":\"col\"},\"type\":\"cmp\"}}}," +
    "{\"id\":\"graph_target_closed_0\",\"in\":[" +
    "\"graph_source_closed_0\",\"graph_nodes_0\"]," +
    "\"op\":\"REL.join\",\"params\":{\"how\":\"semi\"," +
    "\"key_pairs\":[{\"left\":\"dst_id\",\"right\":\"id\"}]," +
    "\"null_key\":\"no_match\",\"on\":{\"left\":{" +
    "\"path\":[\"left\",\"dst_id\"],\"type\":\"col\"}," +
    "\"op\":\"eq\",\"right\":{\"path\":[\"right\",\"id\"]," +
    "\"type\":\"col\"},\"type\":\"cmp\"}}}," +
    "{\"id\":\"graph_0\",\"in\":[\"graph_nodes_0\"," +
    "\"graph_target_closed_0\"]," +
    "\"op\":\"BRIDGE.rows.to_graph\",\"params\":{" +
    "\"edge\":{\"label\":null,\"properties\":[\"weight\"]," +
    "\"source\":\"src_id\",\"target\":\"dst_id\"}," +
    "\"mode\":\"declared_nodes\",\"node\":{" +
    "\"identity\":\"id\",\"properties\":[]}}}]",
  )
}

///|
test "explicit Graph construction accounts for its finite expansion" {
  let checked = explicit_graph_construction_checked()
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
  let exact_sequence = {
    ..sequence_limits(),
    max_bindings: 4,
    max_name_bytes: 20,
    expressions: { ..expression_limits(), max_work: 4, },
  }
  assert_true(
    @lowering_relation.prepare_sequence(owner, exact_sequence) is Ok(_),
  )
  for
    limited in [
      { ..exact_sequence, max_bindings: 3, },
      { ..exact_sequence, max_name_bytes: 19, },
      {
        ..exact_sequence,
        expressions: { ..exact_sequence.expressions, max_work: 3, },
      },
    ] {
    assert_true(@lowering_relation.prepare_sequence(owner, limited) is Err(_))
  }
}

///|
test "explicit Graph construction projects a shared endpoint once" {
  let checked = self_loop_graph_construction_checked()
  let prepared = @lowering_relation.prepare(checked, limits()).unwrap()
  let owner = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  let encoded = @encode.finish(writer)
  assert_true(
    encoded.contains(
      "\"id\":\"graph_edges_0\",\"in\":[\"input_0\"]," +
      "\"op\":\"REL.select\",\"params\":{\"columns\":[" +
      "{\"from\":\"id\",\"to\":\"id\"}]}",
    ),
  )
  assert_false(
    encoded.contains(
      "{\"from\":\"id\",\"to\":\"id\"}," + "{\"from\":\"id\",\"to\":\"id\"}",
    ),
  )
}
