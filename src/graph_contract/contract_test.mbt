///|
fn caps() -> @graph_contract.Limits {
  { max_bytes: 100000, max_nodes: 10000, max_depth: 1000, }
}

///|
fn with_properties(rows : @carrier.Knowledge) -> @carrier.Carrier {
  with_labels(rows, [])
}

///|
fn with_labels(
  rows : @carrier.Knowledge,
  labels : Array[String],
) -> @carrier.Carrier {
  let node = @carrier.graph_node_definition(
    "N",
    [@value.primitive(NumberType, nullable=false)],
    rows,
    labels,
    max_fields=100,
    max_name_bytes=1000,
  ).unwrap()
  let edge = @carrier.graph_edge_definition(
    @carrier.graph_node_definition(
      "E",
      [@value.primitive(NumberType, nullable=false)],
      rows,
      [],
      max_fields=100,
      max_name_bytes=1000,
    ).unwrap(),
    "N",
    "N",
  ).unwrap()
  @carrier.graph(
    "sha256:" + "0".repeat(64),
    [node],
    [edge],
    max_definitions=2,
    max_contract_work=100000,
  ).unwrap()
}

///|
test "complete property types participate independently of enumeration order" {
  let number = @value.primitive(NumberType, nullable=false)
  let text = @value.primitive(StringType, nullable=true)
  let a : Array[(@row.FieldName, @value.Contract?)] = [
    (Unqualified("é"), Some(number)),
    (Unqualified("a"), Some(text)),
  ]
  let b = [a[1], a[0]]
  let left = with_properties(
    @carrier.rows(a, field_set=Closed, max_fields=2, max_name_bytes=10).unwrap(),
  )
  let right = with_properties(
    @carrier.rows(b, field_set=Closed, max_fields=2, max_name_bytes=10).unwrap(),
  )
  let c = @graph_contract.admit(left, caps()).unwrap()
  assert_eq(
    @graph_contract.cid(c),
    @graph_contract.cid(@graph_contract.admit(right, caps()).unwrap()),
  )
  let serialized = @graph_contract.stringify(c, caps())
  let parsed = @canonical.from_json(@json.parse(serialized), 100, 20, 10000)
  assert_eq(serialized, @canonical.stringify_value(parsed, 10000, 100, 20))
  let changed = with_properties(
    @carrier.rows(
      [(Unqualified("a"), Some(number)), a[0]],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=10,
    ).unwrap(),
  )
  assert_true(
    @graph_contract.cid(c) !=
    @graph_contract.cid(@graph_contract.admit(changed, caps()).unwrap()),
  )
  let incomplete = @carrier.rows(
    [(Unqualified("a"), None)],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  assert_true(
    @carrier.graph_node_definition(
      "N",
      [number],
      incomplete,
      [],
      max_fields=1,
      max_name_bytes=1,
    )
    is Err(IncompleteProperties),
  )
}

///|
test "nested contracts are emitted iteratively with depth and node bounds" {
  let mut t = @value.primitive(NumberType, nullable=false)
  for _ in 0..<2000 {
    t = @value.array_contract(t, nullable=false).unwrap()
  }
  let rows = @carrier.rows(
    [(Unqualified("nested"), Some(t))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=6,
  ).unwrap()
  let g = with_properties(rows)
  let large : @graph_contract.Limits = {
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 10000,
  }
  assert_true(@graph_contract.admit(g, large) is Ok(_))
  assert_true(
    @graph_contract.admit(g, { ..large, max_depth: 100, })
    is Err(BudgetExceeded),
  )
  assert_true(
    @graph_contract.admit(g, { ..large, max_nodes: 100, })
    is Err(BudgetExceeded),
  )
}

///|
test "graph contract identity matches independently fixed canonical preimage" {
  let g = @carrier.graph_carrier(
    @graph_contract.graph(
      @graph_contract.read_cursor(read_source(property_body()), caps()).unwrap(),
    ),
  )
  let c = @graph_contract.admit(g, caps()).unwrap()
  // Node canonicalText + crypto SHA-256, independently computed from this body.
  assert_eq(
    @graph_contract.cid(c),
    "sha256:df3a17807922ac2f939372e0cd59b31ecc7e6c860bc22c985aa8acf05971f166",
  )
  let text = @graph_contract.stringify(c, caps())
  assert_eq(@graph_contract.bytes(c), text.length())
  assert_true(@graph_contract.nodes(c) > 0)
  let exact = { ..caps(), max_nodes: @graph_contract.nodes(c), }
  assert_true(@graph_contract.admit(g, exact) is Ok(_))
  assert_true(
    @graph_contract.admit(g, { ..exact, max_nodes: exact.max_nodes - 1, })
    is Err(BudgetExceeded),
  )
  let canonical = @canonical.from_json(@json.parse(text), 1000, 100, 10000)
  assert_eq(@canonical.stringify_value(canonical, 10000, 1000, 100), text)
  assert_eq(
    @canonical.cid_value(canonical, 10000, 1000, 100),
    @graph_contract.cid(c),
  )
  assert_true(
    @graph_contract.admit(g, { ..caps(), max_bytes: text.length(), }) is Ok(_),
  )
  assert_true(
    @graph_contract.admit(g, { ..caps(), max_bytes: text.length() - 1, })
    is Err(BudgetExceeded),
  )
}

///|
test "closed label knowledge is semantic and declaration order is not" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let a = @graph_contract.admit(with_labels(empty, ["b", "a"]), caps()).unwrap()
  let b = @graph_contract.admit(with_labels(empty, ["a", "b"]), caps()).unwrap()
  assert_eq(@graph_contract.cid(a), @graph_contract.cid(b))
  assert_true(
    @graph_contract.cid(a) !=
    @graph_contract.cid(
      @graph_contract.admit(with_labels(empty, []), caps()).unwrap(),
    ),
  )
  let definition = @carrier.graph_node_at(
    @carrier.graph_definition(@graph_contract.graph(a)),
    0,
  ).unwrap()
  assert_eq(@carrier.graph_element_definition_labels(definition), ["a", "b"])
}

///|
test "incomplete graph evidence cannot become a pinned contract" {
  assert_true(
    @graph_contract.admit(@carrier.unknown_carrier(GraphKind), caps())
    is Err(IncompleteGraph),
  )
  let current = with_properties(
    @carrier.rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap(),
  )
  for
    c in [
      { ..caps(), max_nodes: 0, },
      { ..caps(), max_depth: 0, },
      { ..caps(), max_bytes: 0, },
    ] {
    assert_true(@graph_contract.admit(current, c) is Err(BudgetExceeded))
  }
  assert_true(
    @graph_contract.admit(current, { ..caps(), max_nodes: -1, })
    is Err(InvalidLimits),
  )
}
