///|
fn read_source(text : String) -> @decode.Cursor {
  let node = @source.parse_json(text, {
    max_input_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 5000,
  }).unwrap()
  @decode.admit(node, {
    max_nodes: 100000,
    max_depth: 5000,
    max_string_bytes: 1000000,
    max_total_string_bytes: 1000000,
  }).unwrap()
}

///|
fn empty_body() -> String {
  (
    #|{"edge_labels":null,"edge_properties":{},"identity_law_cid":"sha256:ab1ae472462b96ac48e56d3ce0544213cab5d422e6bb198bc9acd5e4d90e0fe4","node_id_contract":{"nullable":false,"type":"number"},"node_properties":{},"value_law_cid":"sha256:ab1ae472462b96ac48e56d3ce0544213cab5d422e6bb198bc9acd5e4d90e0fe4","version":"actql-graph-contract/0.1"}
  )
}

///|
test "read current graph body retains the independently fixed identity and exact limits" {
  let cursor = read_source(property_body())
  let value = @graph_contract.read_cursor(cursor, caps()).unwrap()
  assert_eq(
    @graph_contract.cid(value),
    "sha256:6a0fe1664c431e3b0835ccaf2fff3569e99492ae427eab4ccb65d34096ce604d",
  )
  assert_eq(@graph_contract.stringify(value, caps()), property_body())
  let exact : @graph_contract.Limits = {
    max_bytes: @graph_contract.bytes(value),
    max_nodes: @graph_contract.nodes(value),
    max_depth: caps().max_depth,
  }
  assert_true(@graph_contract.read_cursor(cursor, exact) is Ok(_))
  for
    limits in [
      { ..exact, max_bytes: exact.max_bytes - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_depth: 2, },
    ] {
    assert_true(@graph_contract.read_cursor(cursor, limits) is Err(_))
  }
  assert_true(
    @graph_contract.read_cursor(cursor, { ..exact, max_nodes: -1, })
    is Err(InvalidLimits),
  )
  let again = @graph_contract.admit_graph(@graph_contract.graph(value), caps()).unwrap()
  assert_eq(@graph_contract.cid(again), @graph_contract.cid(value))
}

///|
test "read graph body rejects wrong laws noncanonical labels and untyped properties" {
  let wire = property_body()
  for
    (old, replacement) in [
      (
        "\"version\":\"actql-property-graph-contract/0.1\"", "\"version\":\"unknown\"",
      ),
      ("\"nullable\":false", "\"nullable\":true"),
      ("\"properties\":{}", "\"properties\":{\"x\":null}"),
      ("\"properties\":{}", "\"properties\":[]"),
      ("\"labels\":{\"R\":[]}", "\"labels\":{\"R\":[\"b\",\"a\"]}"),
      ("\"Node\":[\"name\"]", "\"Node\":[\"name\",\"name\"]"),
      ("\"labels\":{\"R\":[]}", "\"labels\":[]"),
      ("\"labels\":{\"R\":[]},", ""),
      ("\"labels\":{\"R\":[]}", "\"labels\":{\"R\":[]},\"extra\":0"),
    ] {
    let changed = wire.replace(old~, new=replacement)
    assert_true(changed != wire)
    assert_true(
      @graph_contract.read_cursor(read_source(changed), caps()) is Err(_),
    )
  }
  for key in ["identity_law_cid", "value_law_cid"] {
    let changed = wire.replace(
      old="\"" + key + "\":\"" + @graph_contract.law_cid() + "\"",
      new="\"" + key + "\":\"sha256:" + "0".repeat(64) + "\"",
    )
    assert_true(
      @graph_contract.read_cursor(read_source(changed), caps())
      is Err(LawMismatch),
    )
  }
  assert_true(
    @graph_contract.read_cursor(read_source(empty_body()), caps())
    is Err(InvalidBody),
  )
}

///|
test "deep typed graph properties round trip without a recursive reader" {
  let mut child = @value.primitive(NumberType, nullable=false)
  for _ in 0..<1000 {
    child = @value.array_contract(child, nullable=false, max_items=None).unwrap()
  }
  let rows = @carrier.rows(
    [(@row.Unqualified("nested"), Some(child))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let limits : @graph_contract.Limits = {
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 2000,
  }
  let original = @graph_contract.admit(with_properties(rows), limits).unwrap()
  let wire = @graph_contract.stringify(original, limits)
  let read = @graph_contract.read_cursor(read_source(wire), limits).unwrap()
  assert_eq(@graph_contract.cid(read), @graph_contract.cid(original))
  assert_eq(@graph_contract.stringify(read, limits), wire)
}

///|
test "graph reader preserves non-string identity domains and recursive property contracts" {
  let identity = "{\"nullable\":false,\"type\":\"number\"}"
  for
    replacement in [
      "{\"nullable\":false,\"type\":\"decimal\",\"precision\":38,\"scale\":19}",
      "{\"nullable\":false,\"type\":\"resource_ref\",\"resource_kind\":\"record\"}",
    ] {
    let wire = property_body().replace(old=identity, new=replacement)
    let value = @graph_contract.read_cursor(read_source(wire), caps()).unwrap()
    let expected = @canonical.from_json(@json.parse(wire), 1000, 100, 100000)
    assert_eq(
      @graph_contract.cid(value),
      @canonical.cid_value(expected, 100000, 1000, 100),
    )
  }
  for
    replacement in [
      "{\"nullable\":false,\"type\":\"json\"}", "{\"nullable\":false,\"type\":\"array\",\"items\":{\"nullable\":false,\"type\":\"number\"}}",
    ] {
    assert_true(
      @graph_contract.read_cursor(
        read_source(property_body().replace(old=identity, new=replacement)),
        caps(),
      )
      is Err(InvalidStructure),
    )
  }
}
