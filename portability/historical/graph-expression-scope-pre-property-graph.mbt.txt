///|
test "graph expression scopes expose semantic roles without implicit bridge columns" {
  let number = @contract.primitive(NumberType, nullable=false)
  let text = @contract.primitive(StringType, nullable=false)
  let properties = @carrier.rows(
    [(Unqualified("title"), Some(text))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  let names = @carrier.graph_row_names(
    Unqualified("node_id"),
    Unqualified("source_id"),
    Unqualified("target_id"),
    Some(Unqualified("edge_type")),
    max_name_bytes=100,
  ).unwrap()
  let g = @carrier.graph(
    number,
    properties,
    properties,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
    label_contract=Some(text),
  ).unwrap()
  let source = cursor("true")
  let nodes = @graph_typing.check_scope(Nodes, source, g, limits()).unwrap()
  let n = @graph_typing.scope_fields(nodes)
  assert_eq(@carrier.field_count(n), 2)
  assert_true(@carrier.lookup(n, Unqualified("node_id")) is Present(_))
  assert_true(@carrier.lookup(n, Unqualified("id")) is Absent)
  let edges = @graph_typing.check_scope(Edges, source, g, limits()).unwrap()
  let e = @graph_typing.scope_fields(edges)
  assert_eq(@carrier.field_count(e), 4)
  for name in ["source_id", "target_id", "edge_type", "title"] {
    assert_true(@carrier.lookup(e, Unqualified(name)) is Present(_))
  }
  for name in ["src", "dst", "rel"] {
    assert_true(@carrier.lookup(e, Unqualified(name)) is Absent)
  }
  let u = @graph_typing.scope_usage(edges)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: 0,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@graph_typing.check_scope(Edges, source, g, exact) is Ok(_))
  assert_true(
    @graph_typing.check_scope(Edges, source, g, {
      ..exact,
      max_work: u.work - 1,
    })
    is Err(_),
  )
  assert_true(
    @graph_typing.check_scope(Edges, source, g, {
      ..exact,
      max_text_bytes: u.text_bytes - 1,
    })
    is Err(_),
  )
}

///|
test "graph expression scopes retain unknown fields and require semantic label evidence" {
  let source = cursor("true")
  let unknown = @graph_typing.check_scope(
    Nodes,
    source,
    @carrier.unknown_carrier(GraphKind),
    limits(),
  ).unwrap()
  assert_true(
    @carrier.lookup(@graph_typing.scope_fields(unknown), Unqualified("id"))
    is Unknown,
  )
  let number = @contract.primitive(NumberType, nullable=false)
  let names = @carrier.graph_row_names(
    Unqualified("node"),
    Unqualified("src_name"),
    Unqualified("dst_name"),
    Some(Unqualified("label_name")),
    max_name_bytes=100,
  ).unwrap()
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let g = @carrier.graph(
    number,
    empty,
    empty,
    labels=Some(["a"]),
    max_labels=1,
    max_label_bytes=1,
    row_names=Some(names),
  ).unwrap()
  let scope = @graph_typing.check_scope(Edges, source, g, limits()).unwrap()
  assert_true(
    @carrier.lookup(
      @graph_typing.scope_fields(scope),
      Unqualified("label_name"),
    )
    is Absent,
  )
  assert_true(
    @graph_typing.check_scope(
      Nodes,
      source,
      @carrier.unknown_carrier(RelationKind),
      limits(),
    )
    is Err(_),
  )
}
