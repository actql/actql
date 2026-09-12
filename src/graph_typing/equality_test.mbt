///|
fn complete_graph(
  id : @contract.Contract,
  property : @contract.Contract,
  label : String,
) -> @carrier.Carrier {
  let node = @carrier.rows(
    [(Unqualified("value"), Some(property))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  let edge = @carrier.rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap()
  @carrier.graph(
    id,
    node,
    edge,
    labels=Some([label]),
    max_labels=1,
    max_label_bytes=100,
  ).unwrap()
}

///|
test "graph equality joins compatible extents without evaluating equality" {
  let id = @contract.primitive(NumberType, nullable=false)
  let a = complete_graph(
    id,
    @contract.primitive(StringType, nullable=false),
    "a",
  )
  let z = complete_graph(
    id,
    @contract.primitive(StringType, nullable=true),
    "b",
  )
  let body = cursor("{\"with\":\"peer\"}")
  let c = @graph_typing.check_equality(body, a, z, limits()).unwrap()
  let out = @carrier.complete_schema(
    @carrier.relation_rows(@graph_typing.equality_output(c)).unwrap(),
  ).unwrap()
  let ty = @row.lookup(out, Unqualified("equal")).unwrap()
  assert_true(ty.shape is Boolean && !ty.nullable)
  assert_eq(@row.field_count(out), 1)
  assert_eq(@graph_typing.equality_with_name(c), "peer")
  assert_eq(
    @carrier.graph_labels(@graph_typing.equality_input(c, Left)),
    Some(["a"]),
  )
  let pending = indexed_obligation_copy(
    @graph_typing.equality_pending(c),
    @graph_typing.equality_pending_count(c),
    i => @graph_typing.equality_pending_at(c, i),
    (a, b) => a == b,
  )
  assert_true(pending.contains(CompareTypedCanonicalGraphs))
  pending.clear()
  assert_eq(
    indexed_obligation_copy(
      @graph_typing.equality_pending(c),
      @graph_typing.equality_pending_count(c),
      i => @graph_typing.equality_pending_at(c, i),
      (a, b) => a == b,
    ).length(),
    4,
  )
  let u = @graph_typing.equality_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@graph_typing.check_equality(body, a, z, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(@graph_typing.check_equality(body, a, z, cap) is Err(_))
  }
}

///|
test "graph equality requires closed compatible identity and property domains" {
  let number = @contract.primitive(NumberType, nullable=false)
  let text = @contract.primitive(StringType, nullable=false)
  let a = complete_graph(number, text, "a")
  for
    b in [
      complete_graph(text, text, "a"),
      complete_graph(number, number, "a"),
      graph(number),
      @carrier.unknown_carrier(GraphKind),
      @carrier.unknown_carrier(RelationKind),
    ] {
    assert_true(
      @graph_typing.check_equality(cursor("{\"with\":\"b\"}"), a, b, limits())
      is Err(_),
    )
  }
  for
    body in [
      "{}", "{\"with\":null}", "{\"with\":\"\"}", "{\"with\":\"b\",\"approximate\":true}",
    ] {
    assert_true(
      @graph_typing.check_equality(cursor(body), a, a, limits()) is Err(_),
    )
  }
}

///|
test "deep property compatibility shares one bounded traversal budget" {
  let mut left = @contract.primitive(StringType, nullable=false)
  let mut right = @contract.primitive(StringType, nullable=true)
  for _ in 0..<500 {
    left = @contract.array_contract(left, nullable=false).unwrap()
    right = @contract.array_contract(right, nullable=false).unwrap()
  }
  let id = @contract.primitive(NumberType, nullable=false)
  let a = complete_graph(id, left, "a")
  let b = complete_graph(id, right, "a")
  let source = cursor("{\"with\":\"b\"}")
  assert_true(@graph_typing.check_equality(source, a, b, limits()) is Ok(_))
  assert_true(
    @graph_typing.check_equality(source, a, b, { ..limits(), max_depth: 100, })
    is Err({ kind: BudgetExceeded, .. }),
  )
}
