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
  let checked = @pipeline.check_carriers(
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
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
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
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"graph_0\",\"in\":[\"input_0\",\"input_0\"]," +
    "\"op\":\"BRIDGE.rows.to_graph\",\"params\":{" +
    "\"edge\":{\"label\":null,\"properties\":[\"weight\"]," +
    "\"source\":\"src_id\",\"target\":\"dst_id\"}," +
    "\"mode\":\"declared_nodes\",\"node\":{" +
    "\"identity\":\"id\",\"properties\":[]}}}]",
  )
}
