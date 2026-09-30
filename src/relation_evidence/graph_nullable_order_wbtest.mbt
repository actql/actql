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
test "nullable Graph edge labels are not Relation ordering keys" {
  let graph = @carrier.graph(
    @contract.primitive(StringType, nullable=false),
    @carrier.unknown_rows(),
    @carrier.unknown_rows(),
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let projection = @projection.check(
    @projection.EdgeRows,
    graph_order_cursor("true"),
    graph,
    { max_work: 100, max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
  ).unwrap()
  let transfer = graph_projection_keys(projection, {
    max_work: 100,
    max_name_bytes: 1000,
  }).unwrap()
  let limit : TransferLimits = { max_work: 100, max_name_bytes: 1000, }
  let selected = key_witness_at(transfer.keys, 0).unwrap()
  assert_true(
    select_key(graph_order_cursor("null"), transfer.keys, CanonicalOrder, limit).unwrap().key
    is None,
  )
  assert_eq(selected.origin, GraphProjectionResult)
  assert_eq(selected.fields.length(), 3)
  let mut saw_nullable_label = false
  for field in selected.fields {
    if field.name == @row.Unqualified("rel") {
      saw_nullable_label = field.contract.unwrap().nullable
    }
  }
  assert_true(saw_nullable_label)
  let ordered = select_graph_order_identity(
    graph_order_cursor("null"),
    transfer.keys,
    limit,
  ).unwrap().key.unwrap()
  assert_eq(key_pending(ordered), [ValidateKeyProducer])
  assert_eq(ordered.fields.length(), 3)
  assert_true(key_graph_projection_producer(ordered) is Some(_))
  assert_true(
    select_graph_order_identity(graph_order_cursor("null"), transfer.keys, {
      max_work: 0,
      max_name_bytes: 1000,
    })
    is Err(_),
  )
  assert_true(
    select_key(graph_order_cursor("null"), transfer.keys, ScalarIdentity, limit).unwrap().key
    is None,
  )
  assert_true(
    select_key(
      graph_order_cursor("null"),
      singleton_key(selected),
      CanonicalOrder,
      limit,
    ).unwrap().key
    is None,
  )
  let forged = { ..selected, producer: None, }
  let unrelated = { ..selected, origin: InputDeclaration, }
  for witness in [forged, unrelated] {
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
