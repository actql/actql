///|
fn delta_field(
  c : @contract.Contract,
  name : String,
) -> @contract.Contract raise {
  guard c.shape is @contract.Object(fields) else { fail("object expected") }
  for i in 0..<@contract.field_count(fields) {
    let f = @contract.field_at(fields, i).unwrap()
    if f.name == name {
      return f.contract
    }
  }
  fail("missing field")
}

///|
test "delta arrays retain full record contracts including empty action sets" {
  let id = @contract.decimal_contract(20, 3, nullable=false).unwrap()
  let a = complete_graph(
    id,
    @contract.primitive(StringType, nullable=false),
    "a",
  )
  let b = complete_graph(
    id,
    @contract.primitive(StringType, nullable=true),
    "b",
  )
  let c = @graph_typing.check_diff(
    cursor("{\"with\":\"target\"}"),
    a,
    b,
    limits(),
  ).unwrap()
  let delta = @graph_typing.diff_contract(c)
  assert_true(
    @graph_typing.check_diff(cursor("{\"with\":\"target\"}"), a, b, {
      ..limits(),
      max_depth: 5,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(!delta.nullable)
  let nodes = delta_field(delta, "nodes")
  let additions = delta_field(nodes, "add")
  guard additions.shape is @contract.Array(record, ..) else {
    fail("array expected")
  }
  assert_true(@contract.type_equal(delta_field(record, "id"), id, 10))
  assert_true(delta_field(delta_field(record, "props"), "value").nullable)
  guard delta_field(nodes, "update").shape is @contract.Array(update, ..) else {
    fail("array expected")
  }
  assert_true(@contract.type_equal(delta_field(update, "before"), record, 20))
  assert_true(@contract.type_equal(delta_field(update, "after"), record, 20))
  guard delta_field(delta_field(delta, "edges"), "remove").shape
    is @contract.Array(edge, ..) else {
    fail("array expected")
  }
  assert_true(@contract.type_equal(delta_field(edge, "src"), id, 10))
  assert_true(delta_field(edge, "rel").nullable)
  assert_eq(
    @carrier.graph_labels(@graph_typing.diff_common_graph(c)),
    Some(["a", "b"]),
  )
  assert_eq(@graph_typing.diff_with_name(c), "target")
  let pending = @graph_typing.diff_pending(c)
  assert_true(pending.contains(BindBaseAndTargetIdentities))
  pending.clear()
  assert_eq(@graph_typing.diff_pending(c).length(), 8)
  let u = @graph_typing.diff_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @graph_typing.check_diff(cursor("{\"with\":\"target\"}"), a, b, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_diff(cursor("{\"with\":\"target\"}"), a, b, cap)
      is Err(_),
    )
  }
}

///|
test "delta wrappers do not collide with property names" {
  let number = @contract.primitive(NumberType, nullable=false)
  let text = @contract.primitive(StringType, nullable=false)
  let properties = @carrier.rows(
    [(Unqualified("id"), Some(text)), (Unqualified("props"), Some(number))],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=7,
  ).unwrap()
  let graph = @carrier.graph(
    number,
    properties,
    properties,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let checked = @graph_typing.check_diff(
    cursor("{\"with\":\"same\"}"),
    graph,
    graph,
    limits(),
  ).unwrap()
  let actions = delta_field(@graph_typing.diff_contract(checked), "nodes")
  guard delta_field(actions, "add").shape is @contract.Array(record, ..) else {
    fail("array expected")
  }
  assert_true(delta_field(record, "id").shape is Number)
  assert_true(delta_field(delta_field(record, "props"), "id").shape is Text(_))
  assert_true(
    delta_field(delta_field(record, "props"), "props").shape is Number,
  )
  assert_true(
    @carrier.graph_labels(@graph_typing.diff_common_graph(checked)) is None,
  )
}
