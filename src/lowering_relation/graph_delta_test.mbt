///|
fn delta_graph_carrier() -> @carrier.Carrier raise {
  let body =
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[],"identity_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","node_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":[]},"name":"N","properties":{}}],"value_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","version":"actql-graph-contract/0.1"}
  let contract = @graph_contract.read_cursor(cursor(body), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  // Independent Node crypto digest of the authored constructor definition.
  assert_eq(
    @graph_contract.cid(contract),
    "sha256:183b5a03d53a1edef82907958e3a40620703dde16b01f617b82a7ecf4ba0f284",
  )
  @carrier.graph_carrier(@graph_contract.graph(contract))
}

///|
test "Delta lowering retains ordered Graph inputs and the formal contract CID" {
  let graph = delta_graph_carrier()
  let pipeline = @pipeline.check_carriers(
    cursor("[{\"from\":\"base\",\"graph_diff\":{\"with\":\"target\"}}]"),
    [("base", graph), ("target", graph)],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let prepared = @lowering_relation.prepare(pipeline, limits()).unwrap()
  let node = @lowering_relation.node_at(prepared, 0).unwrap()
  assert_eq(@lowering_relation.input_ids(node), ["input_0", "input_1"])
  let bound = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(bound, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphDeltaStep(delta)) else {
    fail("Delta step")
  }
  assert_eq(
    @graph.delta_operation(@lowering_relation.graph_delta_checked(delta)),
    @graph.Difference,
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"graph_diff_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.diff\",\"params\":{\"graph_contract_cid\":\"sha256:183b5a03d53a1edef82907958e3a40620703dde16b01f617b82a7ecf4ba0f284\"}}]",
  )
  // Selection still requires the installed Diff policy and exact Graph views;
  // the checked node alone is not a resource/custody receipt.
  assert_true(@lowering_relation.node_supports_selected_managed_execution(node))
  assert_false(@lowering_relation.node_can_split_carrier_transform(node))
  assert_false(@lowering_relation.node_accepts_managed_relation_view(node, 1))
}

///|
test "Delta application lowering binds the selected Relation field without reparsing a Plan" {
  let graph = delta_graph_carrier()
  let updates = @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("changes"),
          Some(@contract.primitive(JsonType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=7,
    ).unwrap(),
  )
  let pipeline = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"base\",\"apply_graph_delta\":{\"with\":\"updates\",\"field\":\"changes\"}}]",
    ),
    [("base", graph), ("updates", updates)],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let prepared = @lowering_relation.prepare(pipeline, limits()).unwrap()
  let bound = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(bound, sequence_limits()).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"apply_graph_delta_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.apply_delta\",\"params\":{\"field\":\"changes\",\"graph_contract_cid\":\"sha256:183b5a03d53a1edef82907958e3a40620703dde16b01f617b82a7ecf4ba0f284\"}}]",
  )
  let node = @lowering_relation.node_at(prepared, 0).unwrap()
  // Registered selected execution still requires the installed provider and
  // the enclosing Plan's independently resolved resources.
  assert_true(@lowering_relation.node_supports_selected_managed_execution(node))
  assert_true(@lowering_relation.node_can_split_carrier_transform(node))
  assert_true(@lowering_relation.node_accepts_managed_carrier_view(node, 0))
  assert_false(@lowering_relation.node_accepts_managed_carrier_view(node, 1))
  assert_false(@lowering_relation.node_accepts_managed_relation_view(node, 0))
  assert_true(@lowering_relation.node_accepts_managed_relation_view(node, 1))
}
