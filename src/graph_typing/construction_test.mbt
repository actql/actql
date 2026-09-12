///|
fn construction_input(nullable : Bool) -> @carrier.Carrier {
  let id = @contract.decimal_contract(20, 3, nullable~).unwrap()
  @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("id"), Some(id)),
        (Unqualified("src_id"), Some(id)),
        (Unqualified("dst_id"), Some(id)),
        (
          Unqualified("edge_type"),
          Some(@contract.primitive(StringType, nullable=true)),
        ),
        (
          Unqualified("rel"),
          Some(@contract.primitive(StringType, nullable=false)),
        ),
        (
          Unqualified("weight"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=6,
      max_name_bytes=100,
    ).unwrap(),
  )
}

///|
test "concise graph closes nodes from typed endpoints and retains non-role properties" {
  let input = construction_input(false)
  let at = cursor("{\"source\":\"src_id\",\"target\":\"dst_id\"}")
  let c = @graph_typing.check_construction(at, None, input, limits()).unwrap()
  guard @graph_typing.construction_output(c) is @carrier.GraphValue(g) else {
    fail("Graph")
  }
  assert_true(
    @carrier.graph_identity(g).shape is Decimal(precision=20, scale=3),
  )
  assert_eq(@carrier.field_count(@carrier.graph_node_properties(g)), 0)
  assert_true(
    @carrier.lookup(@carrier.graph_edge_properties(g), Unqualified("weight"))
    is Present(_),
  )
  assert_true(
    @carrier.lookup(@carrier.graph_edge_properties(g), Unqualified("edge_type"))
    is Absent,
  )
  assert_true(
    @carrier.lookup(@carrier.graph_edge_properties(g), Unqualified("rel"))
    is Present(_),
  )
  assert_true(
    @carrier.graph_label_contract(g)
    is Some({ shape: Text(_), nullable: true, }),
  )
  assert_true(
    indexed_obligation_copy(
      @graph_typing.construction_pending(c),
      @graph_typing.construction_pending_count(c),
      i => @graph_typing.construction_pending_at(c, i),
      (a, b) => a == b,
    ).contains(DeriveDistinctEndpointNodes),
  )
  assert_true(
    indexed_obligation_copy(
      @graph_typing.construction_pending(c),
      @graph_typing.construction_pending_count(c),
      i => @graph_typing.construction_pending_at(c, i),
      (a, b) => a == b,
    ).contains(JournalLabelCompletion),
  )
  let u = @graph_typing.construction_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@graph_typing.check_construction(at, None, input, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_construction(at, None, input, cap) is Err(_),
    )
  }
}

///|
test "explicit branches use only selected properties and do not infer labels" {
  let input = construction_input(false)
  let c = @graph_typing.check_construction(
    cursor(
      (
        #|{"nodes":{"from":"n","id":"id"},"edges":{"from":"e","source":"src_id","target":"dst_id","fields":["edge_type","weight"]}}
      ),
    ),
    Some(input),
    input,
    limits(),
  ).unwrap()
  guard @graph_typing.construction_output(c) is @carrier.GraphValue(g) else {
    fail("Graph")
  }
  assert_eq(@graph_typing.construction_nodes_name(c), Some("n"))
  assert_eq(@graph_typing.construction_edges_name(c), Some("e"))
  assert_eq(@carrier.field_count(@carrier.graph_node_properties(g)), 0)
  assert_true(@carrier.graph_label_contract(g) is None)
  assert_true(
    @carrier.lookup(@carrier.graph_edge_properties(g), Unqualified("edge_type"))
    is Present(_),
  )
  assert_true(
    indexed_obligation_copy(
      @graph_typing.construction_pending(c),
      @graph_typing.construction_pending_count(c),
      i => @graph_typing.construction_pending_at(c, i),
      (a, b) => a == b,
    ).contains(CloseBothEndpointsAgainstDeclaredNodes),
  )
}

///|
test "graph construction rejects malformed shapes nullable identities and duplicate fields" {
  let input = construction_input(false)
  for
    text in [
      "{}", "{\"source\":\"src_id\"}", "{\"source\":\"src_id\",\"target\":\"dst_id\",\"directed\":false}",
      "{\"source\":\"src_id\",\"target\":\"dst_id\",\"label\":\"weight\"}",
    ] {
    assert_true(
      @graph_typing.check_construction(cursor(text), None, input, limits())
      is Err(_),
    )
  }
  assert_true(
    @graph_typing.check_construction(
      cursor("{\"source\":\"src_id\",\"target\":\"dst_id\"}"),
      None,
      construction_input(true),
      limits(),
    )
    is Err({ kind: InvalidConstructionIdentity, .. }),
  )
  let duplicate = @graph_typing.check_construction(
    cursor(
      (
        #|{"nodes":{"from":"n","id":"id","fields":["weight","weight"]},"edges":{"from":"e","source":"src_id","target":"dst_id"}}
      ),
    ),
    Some(input),
    input,
    limits(),
  )
  assert_true(
    duplicate is Err({ kind: DuplicateConstructionField("weight"), .. }),
  )
}
