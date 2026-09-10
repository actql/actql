///|
fn named_graph() -> @carrier.Carrier {
  let id = @contract.decimal_contract(20, 3, nullable=false).unwrap()
  let props = @carrier.rows(
    [
      (
        Unqualified("name"),
        Some(@contract.primitive(StringType, nullable=true)),
      ),
    ],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let names = @carrier.graph_row_names(
    Unqualified("customer_id"),
    Unqualified("source_customer"),
    Unqualified("target_customer"),
    Some(Unqualified("relationship")),
    max_name_bytes=100,
  ).unwrap()
  @carrier.graph(
    id,
    props,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
  ).unwrap()
}

///|
test "partial graph properties remain typed untyped or unknown independently" {
  let props = @carrier.rows(
    [(Unqualified("untyped"), None)],
    field_set=Open,
    max_fields=1,
    max_name_bytes=7,
  ).unwrap()
  let g = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    props,
    props,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let checked = @carrier_projection.check(NodeRows, cursor("true"), g, limits()).unwrap()
  let rows = @carrier.relation_rows(@carrier_projection.output(checked)).unwrap()
  assert_true(
    @carrier.lookup(rows, Unqualified("id"))
    is Present({ contract: Some({ shape: Number, nullable: false, }), .. }),
  )
  assert_true(
    @carrier.lookup(rows, Unqualified("untyped"))
    is Present({ contract: None, .. }),
  )
  assert_true(@carrier.lookup(rows, Unqualified("other")) is Unknown)
}

///|
test "graph bridges retain typed identities properties and semantic aliases" {
  let g = named_graph()
  let id = @contract.decimal_contract(20, 3, nullable=false).unwrap()
  for
    (operation, names) in [
      (@carrier_projection.NodeRows, ["id", "customer_id"]),
      (
        @carrier_projection.EdgeRows,
        ["src", "dst", "source_customer", "target_customer"],
      ),
    ] {
    let checked = @carrier_projection.check(
      operation,
      cursor("true"),
      g,
      limits(),
    ).unwrap()
    let rows = @carrier.relation_rows(@carrier_projection.output(checked)).unwrap()
    assert_eq(@carrier.field_set(rows), Closed)
    for name in names {
      guard @carrier.lookup(rows, Unqualified(name))
        is Present({ contract: Some(c), .. }) else {
        fail("missing identity")
      }
      assert_true(@contract.type_equal(c, id, 10))
    }
    if operation == NodeRows {
      assert_true(
        @carrier.lookup(rows, Unqualified("name"))
        is Present({ contract: Some({ nullable: true, .. }), .. }),
      )
      assert_true(@carrier.lookup(rows, Unqualified("label")) is Absent)
    } else {
      for name in ["rel", "relationship"] {
        assert_true(
          @carrier.lookup(rows, Unqualified(name))
          is Present(
            { contract: Some({ shape: Text(_), nullable: true, }), .. }
          ),
        )
      }
    }
    let u = @carrier_projection.usage(checked)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @carrier_projection.check(operation, cursor("true"), g, exact) is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
      ] {
      assert_true(
        @carrier_projection.check(operation, cursor("true"), g, cap)
        is Err({ kind: BudgetExceeded, .. }),
      )
    }
    assert_eq(@carrier_projection.graph_pending(checked).length(), 4)
  }
}

///|
test "opaque Graph projection retains unknown property and identity evidence" {
  for operation in [@carrier_projection.NodeRows, @carrier_projection.EdgeRows] {
    let checked = @carrier_projection.check(
      operation,
      cursor("true"),
      @carrier.unknown_carrier(GraphKind),
      limits(),
    ).unwrap()
    let rows = @carrier.relation_rows(@carrier_projection.output(checked)).unwrap()
    assert_eq(@carrier.field_set(rows), Open)
    let field = if operation == NodeRows { "id" } else { "src" }
    assert_true(
      @carrier.lookup(rows, Unqualified(field))
      is Present({ contract: None, .. }),
    )
    assert_true(@carrier.lookup(rows, Unqualified("unknown")) is Unknown)
    assert_true(@carrier.complete_schema(rows) is None)
    assert_true(
      @carrier_projection.check(
        operation,
        cursor("false"),
        named_graph(),
        limits(),
      )
      is Err({ kind: InvalidBody, .. }),
    )
    assert_true(
      @carrier_projection.check(
        operation,
        cursor("true"),
        @carrier.unknown_carrier(RelationKind),
        limits(),
      )
      is Err({ kind: WrongCarrier(RelationKind), .. }),
    )
  }
}

///|
test "source role aliases do not change structural contract identity" {
  guard named_graph() is @carrier.GraphValue(g) else { fail("graph expected") }
  let without = @carrier.with_graph_names(g, None)
  let caps : @graph_contract.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }
  assert_eq(
    @graph_contract.cid(@graph_contract.admit(named_graph(), caps).unwrap()),
    @graph_contract.cid(@graph_contract.admit(without, caps).unwrap()),
  )
  assert_true(
    @carrier.graph_row_names(
      Unqualified(""),
      Unqualified("src"),
      Unqualified("dst"),
      None,
      max_name_bytes=100,
    )
    is Err(_),
  )
  assert_true(
    @carrier.graph_row_names(
      Unqualified("id"),
      Unqualified("src"),
      Unqualified("dst"),
      None,
      max_name_bytes=7,
    )
    is Err(_),
  )
}

///|
test "projection rejects collisions without overwriting business properties" {
  let number = @contract.primitive(NumberType, nullable=false)
  let props = @carrier.rows(
    [(Unqualified("id"), Some(number))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  let g = @carrier.graph(
    number,
    props,
    props,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  assert_true(
    @carrier_projection.check(NodeRows, cursor("true"), g, limits())
    is Err({ kind: OutputCollision(Unqualified("id")), .. }),
  )
  guard named_graph() is @carrier.GraphValue(g) else { fail("graph expected") }
  let names = @carrier.graph_row_names(
    Unqualified("name"),
    Unqualified("dst"),
    Unqualified("src"),
    None,
    max_name_bytes=100,
  ).unwrap()
  let bad = @carrier.with_graph_names(g, Some(names))
  for operation in [@carrier_projection.NodeRows, @carrier_projection.EdgeRows] {
    assert_true(
      @carrier_projection.check(operation, cursor("true"), bad, limits())
      is Err({ kind: OutputCollision(_), .. }),
    )
  }
}
