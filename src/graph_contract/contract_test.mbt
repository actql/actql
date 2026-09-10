///|
fn caps() -> @graph_contract.Limits {
  { max_bytes: 100000, max_nodes: 10000, max_depth: 1000, }
}

///|
fn graph(labels : Array[String]?) -> @carrier.Carrier {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  @carrier.graph(
    @value.primitive(NumberType, nullable=false),
    empty,
    empty,
    labels~,
    max_labels=10,
    max_label_bytes=100,
  ).unwrap()
}

///|
fn with_properties(rows : @carrier.Knowledge) -> @carrier.Carrier {
  @carrier.graph(
    @value.primitive(NumberType, nullable=false),
    rows,
    rows,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
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
  let incomplete = with_properties(
    @carrier.rows(
      [(Unqualified("a"), None)],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=1,
    ).unwrap(),
  )
  assert_true(@graph_contract.admit(incomplete, caps()) is Err(IncompleteGraph))
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
  let c = @graph_contract.admit(graph(None), caps()).unwrap()
  // Node canonicalText + crypto SHA-256, independently computed from this body.
  assert_eq(
    @graph_contract.cid(c),
    "sha256:2d338ba9310e353b1891ca91079d3e3fa894afb3f561d97cc444d55698e53e91",
  )
  let text = @graph_contract.stringify(c, caps())
  assert_eq(@graph_contract.bytes(c), text.length())
  assert_true(@graph_contract.nodes(c) > 0)
  let exact = { ..caps(), max_nodes: @graph_contract.nodes(c), }
  assert_true(@graph_contract.admit(graph(None), exact) is Ok(_))
  assert_true(
    @graph_contract.admit(graph(None), {
      ..exact,
      max_nodes: exact.max_nodes - 1,
    })
    is Err(BudgetExceeded),
  )
  let canonical = @canonical.from_json(@json.parse(text), 100, 10, 10000)
  assert_eq(@canonical.stringify_value(canonical, 10000, 100, 10), text)
  assert_eq(
    @canonical.cid_value(canonical, 10000, 100, 10),
    @graph_contract.cid(c),
  )
  assert_true(
    @graph_contract.admit(graph(None), { ..caps(), max_bytes: text.length(), })
    is Ok(_),
  )
  assert_true(
    @graph_contract.admit(graph(None), {
      ..caps(),
      max_bytes: text.length() - 1,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "closed label knowledge is semantic and declaration order is not" {
  let a = @graph_contract.admit(graph(Some(["b", "a"])), caps()).unwrap()
  let b = @graph_contract.admit(graph(Some(["a", "b"])), caps()).unwrap()
  assert_eq(@graph_contract.cid(a), @graph_contract.cid(b))
  assert_true(
    @graph_contract.cid(@graph_contract.admit(graph(None), caps()).unwrap()) !=
    @graph_contract.cid(@graph_contract.admit(graph(Some([])), caps()).unwrap()),
  )
  assert_eq(@carrier.graph_label_count(@graph_contract.graph(a)), Some(2))
  assert_eq(@carrier.graph_label_at(@graph_contract.graph(a), 0), Some("a"))
  assert_true(@carrier.graph_label_at(@graph_contract.graph(a), -1) is None)
  assert_true(@carrier.graph_label_at(@graph_contract.graph(a), 2) is None)
}

///|
test "incomplete graph evidence cannot become a pinned contract" {
  assert_true(
    @graph_contract.admit(@carrier.unknown_carrier(GraphKind), caps())
    is Err(IncompleteGraph),
  )
  let unknown = @carrier.unknown_rows()
  let g = @carrier.graph(
    @value.primitive(NumberType, nullable=false),
    unknown,
    unknown,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  assert_true(@graph_contract.admit(g, caps()) is Err(IncompleteGraph))
  for
    c in [
      { ..caps(), max_nodes: 0, },
      { ..caps(), max_depth: 0, },
      { ..caps(), max_bytes: 0, },
    ] {
    assert_true(@graph_contract.admit(graph(None), c) is Err(BudgetExceeded))
  }
  assert_true(
    @graph_contract.admit(graph(None), { ..caps(), max_nodes: -1, })
    is Err(InvalidLimits),
  )
}
