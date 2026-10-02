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
  let node = @carrier.property_node_definition(
    "Customer",
    [id],
    props,
    ["Customer"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    [],
    max_definitions=1,
    max_contract_work=100,
  ).unwrap()
}

///|
test "definition scoped properties never become an implicit homogeneous projection" {
  for operation in [@carrier_projection.NodeRows, @carrier_projection.EdgeRows] {
    assert_true(
      @carrier_projection.check(
        operation,
        cursor("true"),
        named_graph(),
        limits(),
      )
      is Err({ kind: UnsupportedGraphOperation, .. }),
    )
  }
}

///|
test "unconnected graph projection refuses even exact inspection budgets" {
  for operation in [@carrier_projection.NodeRows, @carrier_projection.EdgeRows] {
    for
      cap in [
        limits(),
        { ..limits(), max_work: 1, max_nodes: 1, max_text_bytes: 0, },
      ] {
      assert_true(
        @carrier_projection.check(operation, cursor("true"), named_graph(), cap)
        is Err({ kind: UnsupportedGraphOperation, .. }),
      )
    }
  }
}

///|
test "opaque Graph cannot fabricate unknown tuple identity or property evidence" {
  for operation in [@carrier_projection.NodeRows, @carrier_projection.EdgeRows] {
    assert_true(
      @carrier_projection.check(
        operation,
        cursor("true"),
        @carrier.unknown_carrier(GraphKind),
        limits(),
      )
      is Err({ kind: IncompleteGraph, .. }),
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
test "graph projection preserves body and budget diagnostics before unsupported refusal" {
  for operation in [@carrier_projection.NodeRows, @carrier_projection.EdgeRows] {
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
      @carrier_projection.check(operation, cursor("true"), named_graph(), {
        ..limits(),
        max_work: 0,
      })
      is Err({ kind: BudgetExceeded, .. }),
    )
    assert_true(
      @carrier_projection.check(operation, cursor("true"), named_graph(), {
        ..limits(),
        max_nodes: -1,
      })
      is Err({ kind: InvalidLimits, .. }),
    )
  }
}

///|
test "business property named id remains definition owned and does not trigger tuple alias synthesis" {
  let properties = @carrier.rows(
    [(Unqualified("id"), Some(@contract.primitive(StringType, nullable=false)))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  let node = @carrier.property_node_definition(
    "N",
    [@contract.primitive(NumberType, nullable=false)],
    properties,
    ["Node"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let graph = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    [],
    max_definitions=1,
    max_contract_work=100,
  ).unwrap()
  for operation in [@carrier_projection.NodeRows, @carrier_projection.EdgeRows] {
    assert_true(
      @carrier_projection.check(operation, cursor("true"), graph, limits())
      is Err({ kind: UnsupportedGraphOperation, .. }),
    )
  }
}
