///|
test "path contracts retain typed edge identity tuples without synthetic strings" {
  let id = @contract.decimal_contract(38, 9, nullable=false).unwrap()
  let g = complete_graph(
    id,
    @contract.primitive(BooleanType, nullable=false),
    "a",
  )
  for kind in [@graph_typing.TraversedPaths, @graph_typing.ShortestPaths] {
    let c = @graph_typing.check_path_contract(kind, cursor("true"), g, limits()).unwrap()
    let rows = @carrier.complete_schema(
      @carrier.relation_rows(@graph_typing.path_output(c)).unwrap(),
    ).unwrap()
    let edges = @row.lookup(rows, Unqualified("edge_ids")).unwrap()
    guard edges.shape is @contract.Array(edge, ..) else {
      abort("expected edge array")
    }
    let edge_fields = @row.from_object(edge).unwrap()
    assert_eq(@row.field_count(edge_fields), 3)
    assert_true(
      @contract.type_equal(
        @row.lookup(edge_fields, Unqualified("src")).unwrap(),
        id,
        20,
      ),
    )
    assert_true(
      @contract.type_equal(
        @row.lookup(edge_fields, Unqualified("dst")).unwrap(),
        id,
        20,
      ),
    )
    assert_true(@row.lookup(edge_fields, Unqualified("rel")).unwrap().nullable)
    let u = @graph_typing.path_usage(c)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @graph_typing.check_path_contract(kind, cursor("true"), g, exact) is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
        { ..exact, max_depth: 1, },
      ] {
      assert_true(
        @graph_typing.check_path_contract(kind, cursor("true"), g, cap)
        is Err(_),
      )
    }
  }
  assert_true(
    @graph_typing.check_path_contract(
      TraversedPaths,
      cursor("true"),
      @carrier.unknown_carrier(GraphKind),
      limits(),
    )
    is Err(_),
  )
}
