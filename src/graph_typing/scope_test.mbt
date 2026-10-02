///|
fn current_scope_graph() -> @carrier.Carrier {
  let number = @contract.primitive(NumberType, nullable=false)
  let text = @contract.primitive(StringType, nullable=false)
  let properties = @carrier.rows(
    [(Unqualified("title"), Some(text))],
    field_set=Closed,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let node = @carrier.property_node_definition(
    "N",
    [number, text],
    properties,
    ["Node"],
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let edge_element = @carrier.property_node_definition(
    "E",
    [text],
    properties,
    ["Edge"],
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let edge = @carrier.property_edge_definition(edge_element, "N", "N").unwrap()
  @carrier.property_graph(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    [node],
    [edge],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
}

///|
test "definition-selected MATCH scopes keep independent identities and business properties" {
  let graph = current_scope_graph()
  for
    (entity, body, names, absent) in [
      (
        @graph_typing.Nodes,
        "{\"definition\":\"N\",\"label\":\"Node\",\"bindings\":{\"identity\":\"node_id\"},\"where\":\"true\",\"fields\":[\"node_id\",\"title\"]}",
        ["node_id", "title"],
        ["id", "Node", "edge_type"],
      ),
      (
        @graph_typing.Edges,
        "{\"definition\":\"E\",\"label\":\"Edge\",\"bindings\":{\"identity\":\"edge_id\",\"source\":\"source_id\",\"target\":\"target_id\"},\"where\":\"true\",\"fields\":[\"edge_id\",\"source_id\",\"target_id\",\"title\"]}",
        ["edge_id", "source_id", "target_id", "title"],
        ["src", "dst", "rel", "Edge", "edge_type"],
      ),
    ] {
    let source = cursor(body)
    let checked = @graph_typing.check_match(
      entity,
      source,
      graph,
      None,
      predicate_limits(),
    ).unwrap()
    let scope = @graph_typing.match_property_scope_fields(checked)
    assert_eq(@carrier.field_count(scope), names.length())
    for name in names {
      assert_true(@carrier.lookup(scope, Unqualified(name)) is Present(_))
    }
    for name in absent {
      assert_true(@carrier.lookup(scope, Unqualified(name)) is Absent)
    }
    // Identity is a typed-domain JSON value; neither endpoints nor label
    // strings manufacture the independent edge key.
    let identity = if entity == @graph_typing.Nodes {
      "node_id"
    } else {
      "edge_id"
    }
    guard @carrier.lookup(scope, Unqualified(identity)) is Present(field) &&
      field.contract is Some(contract) else {
      abort("missing identity binding")
    }
    assert_true(contract.shape is @contract.Json)
    let usage = @graph_typing.match_usage(checked)
    let exact = {
      ..predicate_limits(),
      max_work: usage.work,
      max_nodes: usage.nodes,
      max_text_bytes: usage.text_bytes,
      max_tokens: usage.tokens,
    }
    assert_true(
      @graph_typing.check_match(entity, source, graph, None, exact) is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: usage.work - 1, },
        { ..exact, max_text_bytes: usage.text_bytes - 1, },
      ] {
      assert_true(
        @graph_typing.check_match(entity, source, graph, None, cap) is Err(_),
      )
    }
  }
}
