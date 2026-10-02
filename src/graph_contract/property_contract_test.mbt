///|
fn property_body() -> String {
  (
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[{"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"R":[]},"name":"E","properties":{},"source_definition":"N","target_definition":"N"}],"identity_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","node_definitions":[{"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":["name"],"Person":[]},"name":"N","properties":{"name":{"nullable":true,"type":"string"}}}],"value_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","version":"actql-property-graph-contract/0.1"}
  )
}

///|
test "measured Graph JSON size does not become the remaining type comparison budget" {
  let root = read_source(property_body())
  let baseline = @graph_contract.read_property_graph_cursor(root, caps()).unwrap()
  let measured = {
    ..caps(),
    max_bytes: @graph_contract.property_bytes(baseline),
    max_nodes: @graph_contract.property_nodes(baseline),
  }
  // These are exact structural limits, not permission to reset or omit the
  // additional graph-wide type/label comparison accounting.
  let restored = @graph_contract.read_property_graph_cursor(root, measured).unwrap()
  assert_eq(
    @graph_contract.property_cid(restored),
    @graph_contract.property_cid(baseline),
  )
  let (admitted, work) = @graph_contract.read_property_graph_cursor_usage(
    root,
    measured,
    max_contract_work=1000,
  ).unwrap()
  assert_true(work > 0)
  assert_eq(
    @graph_contract.property_cid(admitted),
    @graph_contract.property_cid(baseline),
  )
  assert_true(
    @graph_contract.read_property_graph_cursor_usage(
      root,
      measured,
      max_contract_work=work,
    )
    is Ok(_),
  )
  assert_true(
    @graph_contract.read_property_graph_cursor_usage(
      root,
      measured,
      max_contract_work=work - 1,
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    @graph_contract.read_property_graph_cursor_usage(
      root,
      { ..measured, max_nodes: measured.max_nodes - 1, },
      max_contract_work=work,
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    @graph_contract.read_property_graph_cursor_usage(
      root,
      measured,
      max_contract_work=-1,
    )
    is Err(InvalidLimits),
  )
}

///|
test "external Property Graph admission checks graph wide types and shared node edge label sets" {
  let wrong_type = property_body().replace(
    old="\"properties\":{}",
    new="\"properties\":{\"NAME\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  assert_true(
    @graph_contract.read_property_graph_cursor(read_source(wrong_type), caps())
    is Err(InvalidStructure),
  )
  let wrong_label = property_body()
    .replace(
      old="\"labels\":{\"R\":[]}",
      new="\"labels\":{\"NODE\":[\"NAME\",\"score\"]}",
    )
    .replace(
      old="\"properties\":{}",
      new="\"properties\":{\"NAME\":{\"nullable\":false,\"type\":\"string\"},\"score\":{\"nullable\":false,\"type\":\"number\"}}",
    )
  assert_true(
    @graph_contract.read_property_graph_cursor(read_source(wrong_label), caps())
    is Err(InvalidStructure),
  )
  let compatible = property_body()
    .replace(
      old="\"labels\":{\"R\":[]}",
      new="\"labels\":{\"NODE\":[\"NAME\"]}",
    )
    .replace(
      old="\"properties\":{}",
      new="\"properties\":{\"NAME\":{\"nullable\":false,\"type\":\"string\"}}",
    )
  assert_true(
    @graph_contract.read_property_graph_cursor(read_source(compatible), caps())
    is Ok(_),
  )
}

///|
test "separate property graph contract preserves an independently authored body and CID" {
  let read = @graph_contract.read_property_graph_cursor(
    read_source(property_body()),
    caps(),
  ).unwrap()
  // Node crypto SHA-256 of the literal canonical body, not of product output.
  assert_eq(
    @graph_contract.property_cid(read),
    "sha256:3e06c160155f0542561eab6a31c31422a78e7a749490ff5b24fb0ce4c7ff3321",
  )
  assert_eq(
    @graph_contract.stringify_property_graph(read, caps()),
    property_body(),
  )
  let profile = @carrier.graph_property_definition(
    @graph_contract.property_graph(read),
  )
  assert_eq(@carrier.property_graph_node_count(profile), 1)
  assert_eq(@carrier.property_graph_edge_count(profile), 1)
  let node = @carrier.property_graph_node_at(profile, 0).unwrap()
  let exposed = @carrier.property_definition_label_properties(node)
  assert_eq(exposed.length(), 2)
  assert_eq(@carrier.field_count(exposed[0].1), 1)
  assert_eq(@carrier.field_count(exposed[1].1), 0)
  assert_true(
    @carrier.field_at(@carrier.property_definition_properties(node), 0).unwrap().contract.unwrap().nullable,
  )
  let issued = @graph_contract.admit_property_graph(
    @carrier.graph_carrier(@graph_contract.property_graph(read)),
    caps(),
  ).unwrap()
  assert_eq(
    @graph_contract.property_cid(issued),
    @graph_contract.property_cid(read),
  )
}

///|
test "all graph admission entry points share one current contract and reject historical bodies" {
  let read = @graph_contract.read_cursor(read_source(property_body()), caps()).unwrap()
  assert_eq(
    @graph_contract.cid(read),
    "sha256:3e06c160155f0542561eab6a31c31422a78e7a749490ff5b24fb0ce4c7ff3321",
  )
  assert_eq(@graph_contract.stringify(read, caps()), property_body())
  let admitted = @graph_contract.admit_graph(
    @graph_contract.graph(read),
    caps(),
  ).unwrap()
  assert_eq(@graph_contract.cid(admitted), @graph_contract.property_cid(read))
  assert_eq(
    @graph_contract.bytes(admitted),
    @graph_contract.property_bytes(read),
  )
  assert_eq(
    @graph_contract.nodes(admitted),
    @graph_contract.property_nodes(read),
  )
  assert_eq(@graph_contract.law_cid(), @graph_contract.property_law_cid())
  for
    rejected in [
      empty_body(),
      property_body().replace(
        old="actql-property-graph-contract/0.1",
        new="actql-graph-contract/0.1",
      ),
    ] {
    assert_true(
      @graph_contract.read_cursor(read_source(rejected), caps())
      is Err(InvalidBody),
    )
    assert_true(
      @graph_contract.read_property_graph_cursor(read_source(rejected), caps())
      is Err(InvalidBody),
    )
  }
  assert_true(
    @graph_contract.admit_property_graph(graph(None), caps())
    is Err(IncompleteGraph),
  )
  assert_true(
    @graph_contract.admit(graph(None), caps()) is Err(IncompleteGraph),
  )
}

///|

///|
test "property graph contract rejects mismatched profile laws keys labels and endpoints" {
  for
    (old, replacement) in [
      ("actql-property-graph-contract/0.1", "actql-graph-contract/0.1"),
      (
        "\"key_contracts\":[{\"nullable\":false,\"type\":\"number\"}]", "\"key_contracts\":[]",
      ),
      ("\"nullable\":false", "\"nullable\":true"),
      ("\"type\":\"number\"", "\"type\":\"json\""),
      ("\"Node\":[\"name\"]", "\"Node\":[\"missing\"]"),
      ("\"Node\":[\"name\"]", "\"Node\":[\"name\",\"name\"]"),
      ("\"target_definition\":\"N\"", "\"target_definition\":\"Missing\""),
      ("\"domain\":\"sha256:", "\"unknown\":0,\"domain\":\"sha256:"),
    ] {
    assert_true(
      @graph_contract.read_property_graph_cursor(
        read_source(property_body().replace(old~, new=replacement)),
        caps(),
      )
      is Err(_),
    )
  }
  assert_true(
    @graph_contract.read_property_graph_cursor(
      read_source(
        property_body().replace(
          old=@graph_contract.property_law_cid(),
          new="sha256:ab1ae472462b96ac48e56d3ce0544213cab5d422e6bb198bc9acd5e4d90e0fe4",
        ),
      ),
      caps(),
    )
    is Err(LawMismatch),
  )
}

///|
test "property graph schema uses existing bounded encoding and admission limits" {
  let value = @graph_contract.read_property_graph_cursor(
    read_source(property_body()),
    caps(),
  ).unwrap()
  for
    limits in [
      { ..caps(), max_bytes: @graph_contract.property_bytes(value) - 1, },
      { ..caps(), max_nodes: 1, },
      { ..caps(), max_depth: 2, },
      { ..caps(), max_nodes: -1, },
    ] {
    assert_true(
      @graph_contract.read_property_graph_cursor(
        read_source(property_body()),
        limits,
      )
      is Err(_),
    )
    assert_true(
      @graph_contract.admit_property_graph(
        @carrier.graph_carrier(@graph_contract.property_graph(value)),
        limits,
      )
      is Err(_),
    )
  }
}
