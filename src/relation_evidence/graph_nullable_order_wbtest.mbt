///|
fn graph_order_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 10,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
test "typed Graph identity evidence cannot grant generic JSON or historical tuple ordering" {
  let props = @carrier.rows(
    [
      (
        @row.Unqualified("label"),
        Some(@contract.primitive(StringType, nullable=true)),
      ),
    ],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let node = @carrier.property_node_definition(
    "N",
    [@contract.primitive(StringType, nullable=false)],
    props,
    ["Node"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let edge = @carrier.property_edge_definition(
    @carrier.property_node_definition(
      "E",
      [@contract.primitive(StringType, nullable=false)],
      props,
      ["Link"],
      max_fields=1,
      max_name_bytes=100,
    ).unwrap(),
    "N",
    "N",
  ).unwrap()
  let graph = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    [edge],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
  let matched = @graph.check_match(
    @graph.Edges,
    graph_order_cursor(
      "{\"definition\":\"E\",\"bindings\":{\"identity\":\"element\",\"source\":\"src\",\"target\":\"dst\"},\"where\":\"true\",\"fields\":[\"element\",\"src\",\"dst\",\"label\"]}",
    ),
    graph,
    None,
    {
      max_work: 10000,
      max_nodes: 100,
      max_depth: 20,
      max_text_bytes: 1000,
      max_tokens: 1000,
    },
  ).unwrap()
  let limit : TransferLimits = { max_work: 100, max_name_bytes: 1000, }
  let transfer = graph_query_keys(MatchOperation(matched), limit).unwrap()
  let selected = key_witness_at(transfer.keys, 0).unwrap()
  assert_eq(selected.origin, GraphQueryResult)
  assert_eq(selected.fields.length(), 1)
  assert_eq(selected.fields[0].name, @row.Unqualified("element"))
  assert_true(selected.fields[0].contract.unwrap().shape is @contract.Json)
  assert_false(selected.fields[0].contract.unwrap().nullable)
  assert_eq(key_pending(selected), [ValidateKeyProducer])
  assert_true(key_graph_query_producer(selected) is Some(MatchOperation(_)))
  // Nullable business properties and endpoints are not edge identity components.
  assert_true(
    select_graph_order_identity(
      graph_order_cursor("null"),
      transfer.keys,
      limit,
    ).unwrap().key
    is None,
  )
  for usage in [CanonicalOrder, ScalarIdentity] {
    assert_true(
      select_key(graph_order_cursor("null"), transfer.keys, usage, limit).unwrap().key
      is None,
    )
  }
  assert_true(
    select_graph_order_identity(graph_order_cursor("null"), transfer.keys, {
      max_work: 0,
      max_name_bytes: 1000,
    })
    is Err(_),
  )
  for
    witness in [
      { ..selected, producer: None, },
      { ..selected, origin: InputDeclaration, },
    ] {
    let keys = singleton_key(witness)
    assert_true(
      select_graph_order_identity(graph_order_cursor("null"), keys, limit).unwrap().key
      is None,
    )
    assert_true(
      select_key(graph_order_cursor("null"), keys, CanonicalOrder, limit).unwrap().key
      is None,
    )
  }
}
