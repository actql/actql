///|
fn limits() -> Limits {
  {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
    value_limits: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  }
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
// Independently authored contract and preimage, also fixed in the owned corpus.
fn schema() -> String {
  (
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[{"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"R":[]},"name":"E","properties":{},"source_definition":"N","target_definition":"N"}],"identity_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","node_definitions":[{"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":["name"],"Person":[]},"name":"N","properties":{"name":{"nullable":true,"type":"string"}}}],"value_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","version":"actql-property-graph-contract/0.1"}
  )
}

///|
fn builder() -> Builder {
  prepare_property(
    @graph.read_property_graph_cursor(cursor(schema()), {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
    limits(),
  ).unwrap()
}

///|
fn number(value : Double) -> @value.CheckedValue {
  @value.checked_number_value(
    value,
    @contract.primitive(NumberType, nullable=false),
  ).unwrap()
}

///|
fn identity(definition : String, key : Int) -> @value.CheckedValue {
  let body = "{\"definition\":\"" +
    definition +
    "\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[" +
    key.to_string() +
    "],\"key_types\":[{\"kind\":\"number\"}]}"
  @value.admit(
    @contract.primitive(JsonType, nullable=false),
    cursor(body),
    limits().value_limits,
  ).unwrap()
}

///|
test "sole graph snapshot identity retains independent edge keys and fixed preimage" {
  let out = builder()
  let node = identity("N", 1)
  begin_property_node(out, node, [number(1.0)]).unwrap()
  append_property(
    out,
    "name",
    @value.recheck_runtime_value(
      @value.checked_text_value(
        "one",
        @contract.primitive(StringType, nullable=false),
      ).unwrap().value,
      @contract.primitive(StringType, nullable=true),
      limits().value_limits,
    ).unwrap(),
  ).unwrap()
  end_node(out).unwrap()
  end_nodes(out).unwrap()
  for key in [10, 11] {
    begin_property_edge(
      out,
      identity("E", key),
      [number(key.to_double())],
      node,
      node,
    ).unwrap()
    end_property_edge(out).unwrap()
  }
  let (cid, _) = finish_property(out).unwrap()
  // SHA-256 of the independent owned corpus, never of product-derived expectations.
  assert_eq(
    cid, "sha256:4d6e1221c4244ab1074b836a651e7b4522fcdfefa86414121b7529a715b60b1a",
  )
  assert_true(drain_property_output(out) is Err(InvalidPhase))
  assert_true(finish_property(out) is Err(InvalidPhase))
}

///|
test "current snapshot identity rejects reversed node and property order" {
  let nodes = builder()
  begin_property_node(nodes, identity("N", 2), [number(2.0)]).unwrap()
  end_node(nodes).unwrap()
  assert_true(
    begin_property_node(nodes, identity("N", 1), [number(1.0)])
    is Err(InvalidNodeOrder),
  )
  let properties = builder()
  begin_property_node(properties, identity("N", 1), [number(1.0)]).unwrap()
  append_property(properties, "z", number(1.0)).unwrap()
  assert_true(
    append_property(properties, "a", number(1.0)) is Err(InvalidPropertyOrder),
  )
}

///|
test "parallel edge ordering uses independent identity not endpoints or labels" {
  let out = builder()
  end_nodes(out).unwrap()
  let node = identity("N", 1)
  begin_property_edge(out, identity("E", 11), [number(11.0)], node, node).unwrap()
  end_property_edge(out).unwrap()
  assert_true(
    begin_property_edge(out, identity("E", 10), [number(10.0)], node, node)
    is Err(InvalidEdgeOrder),
  )
  assert_true(
    begin_property_edge(out, identity("E", 11), [number(11.0)], node, node)
    is Err(InvalidEdgeOrder),
  )
}

///|
test "snapshot writer phase prevents partial completion and invalid limits" {
  let out = builder()
  begin_property_node(out, identity("N", 1), [number(1.0)]).unwrap()
  assert_true(finish_property(out) is Err(InvalidPhase))
  assert_true(end_property_edge(out) is Err(InvalidPhase))
  assert_true(drain_property_output(out) is Ok(_))
  let checked = @graph.read_property_graph_cursor(cursor(schema()), {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  assert_true(
    prepare_property(checked, { ..limits(), max_bytes: -1, })
    is Err(InvalidLimits),
  )
}
