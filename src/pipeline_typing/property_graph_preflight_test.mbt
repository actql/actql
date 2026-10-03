///|
fn property_preflight_graph(nested : Bool, edge : Bool) -> @carrier.Carrier {
  let number = @contract.primitive(NumberType, nullable=false)
  let mut contract = number
  if nested {
    for _ in 0..<6 {
      contract = @contract.array_contract(contract, nullable=false).unwrap()
    }
  }
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let properties = @carrier.rows(
    [(Unqualified("detail"), Some(contract))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let node = @carrier.property_node_definition(
    "N",
    [number],
    if edge {
      empty
    } else {
      properties
    },
    ["Node"],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let edges = if edge {
    let element = @carrier.property_node_definition(
      "E",
      [number, @contract.primitive(StringType, nullable=false)],
      properties,
      ["Connection"],
      max_fields=10,
      max_name_bytes=100,
    ).unwrap()
    [@carrier.property_edge_definition(element, "N", "N").unwrap()]
  } else {
    []
  }
  @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    edges,
    max_definitions=2,
    max_contract_work=10000,
  ).unwrap()
}

///|
test "Graph preflight charges composite keys static labels and endpoint definitions" {
  let number = @contract.primitive(NumberType, nullable=false)
  let text = @contract.primitive(StringType, nullable=false)
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let node = fn(keys, labels) {
    @carrier.property_node_definition(
      "N",
      keys,
      empty,
      labels,
      max_fields=10,
      max_name_bytes=100,
    ).unwrap()
  }
  let base = node([number], [])
  let edge = @carrier.property_edge_definition(
    @carrier.property_node_definition(
      "E",
      [number],
      empty,
      [],
      max_fields=10,
      max_name_bytes=100,
    ).unwrap(),
    "N",
    "N",
  ).unwrap()
  let usage = fn(nodes, edges) {
    let graph = @carrier.property_graph(
      "sha256:" + "0".repeat(64),
      nodes,
      edges,
      max_definitions=2,
      max_contract_work=10000,
    ).unwrap()
    @pipeline_typing.usage(
      @pipeline_typing.check_carriers(
        cursor("[]"),
        [("g", graph)],
        None,
        None,
        limits(),
      ).unwrap(),
    )
  }
  let before = usage([base], [])
  let composite = usage([node([number, text], [])], [])
  assert_eq(composite.work - before.work, 2)
  assert_eq(composite.text_bytes, before.text_bytes)
  let labelled = usage([node([number], ["Node"])], [])
  assert_eq(labelled.work - before.work, 2)
  assert_eq(labelled.text_bytes - before.text_bytes, 4)
  let connected = usage([base], [edge])
  // Edge occurrence, element name, key slot/type, empty property schema and
  // both endpoint-definition references are visited, not endpoint data IDs.
  assert_eq(connected.work - before.work, 7)
  assert_eq(connected.text_bytes - before.text_bytes, 3)
}

///|
test "unused current Graph definitions cannot bypass nested property preflight" {
  for edge in [false, true] {
    let inputs = [("g", property_preflight_graph(true, edge))]
    assert_true(
      @pipeline_typing.check_carriers(cursor("[]"), inputs, None, None, {
        ..limits(),
        max_depth: 2,
      })
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}

///|
test "current Graph preflight budgets include every definition key property and label" {
  for edge in [false, true] {
    let inputs = [("g", property_preflight_graph(true, edge))]
    let checked = @pipeline_typing.check_carriers(
      cursor("[]"),
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    let used = @pipeline_typing.usage(checked)
    let flat = @pipeline_typing.check_carriers(
      cursor("[]"),
      [("g", property_preflight_graph(false, edge))],
      None,
      None,
      limits(),
    ).unwrap()
    // Each of the six added array contracts is visited both in the complete
    // definition and in its admitted label's public property schema.
    assert_eq(used.work - @pipeline_typing.usage(flat).work, 12)
    let exact = {
      ..limits(),
      max_work: used.work,
      max_text_bytes: used.text_bytes,
      max_nodes: used.nodes,
      max_tokens: used.tokens,
    }
    assert_true(
      @pipeline_typing.check_carriers(cursor("[]"), inputs, None, None, exact)
      is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: used.work - 1, },
        { ..exact, max_text_bytes: used.text_bytes - 1, },
      ] {
      assert_true(
        @pipeline_typing.check_carriers(cursor("[]"), inputs, None, None, cap)
        is Err({ kind: BudgetExceeded, .. }),
      )
    }
  }
}
