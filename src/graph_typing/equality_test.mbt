///|
test "current Graph equality binds two admitted definition domains and one Boolean row" {
  let source = cursor("{\"with\":\"peer\"}")
  let graph = keyed_profile()
  let checked = @graph_typing.check_graph_equality(
    source,
    graph,
    graph,
    limits(),
  ).unwrap()
  for side in [false, true] {
    guard @graph_typing.graph_equality_input(checked, right=side)
      is @carrier.GraphValue(value) else {
      fail("expected a current Graph input")
    }
    assert_eq(
      @carrier.graph_domain(@carrier.graph_definition(value)),
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    )
  }
  let rows = @carrier.complete_schema(
    @carrier.relation_rows(@graph_typing.graph_equality_output(checked)).unwrap(),
  ).unwrap()
  assert_true(
    @row.lookup(rows, Unqualified("equal"))
    is Some({ shape: Boolean, nullable: false, }),
  )
  let usage = @graph_typing.graph_equality_usage(checked)
  let exact = {
    ..limits(),
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
  }
  assert_true(
    @graph_typing.check_graph_equality(source, graph, graph, exact) is Ok(_),
  )
  for
    short in [
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_nodes: usage.nodes - 1, },
      { ..exact, max_text_bytes: usage.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_graph_equality(source, graph, graph, short) is Err(_),
    )
  }
}

///|
test "current Graph equality admits compatible definitions with distinct provenance" {
  let original = keyed_profile()
  guard original is @carrier.GraphValue(graph) else {
    fail("expected current Graph")
  }
  let definition = @carrier.graph_definition(graph)
  let other = @carrier.graph(
    "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    @carrier.graph_node_definitions(definition),
    @carrier.graph_edge_definitions(definition),
    max_definitions=100,
    max_contract_work=10000,
  ).unwrap()
  assert_true(
    @graph_typing.check_graph_equality(
      cursor("{\"with\":\"peer\"}"),
      original,
      other,
      limits(),
    )
    is Ok(_),
  )
}

///|
test "current Graph equality refuses incompatible closed definitions" {
  let empty = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let node = @carrier.graph_node_definition(
    "N",
    [@contract.primitive(@contract.StringType, nullable=false)],
    empty,
    ["Node"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let foreign = @carrier.graph(
    "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    [node],
    [],
    max_definitions=1,
    max_contract_work=100,
  ).unwrap()
  let issue = @graph_typing.check_graph_equality(
    cursor("{\"with\":\"peer\"}"),
    keyed_profile(),
    foreign,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, @graph_typing.IncompatibleGraphDomains)
  assert_true(
    @graph_typing.check_graph_equality(
      cursor("{\"with\":\"peer\"}"),
      keyed_profile(),
      @carrier.unknown_carrier(GraphKind),
      limits(),
    )
    is Err(_),
  )
}
