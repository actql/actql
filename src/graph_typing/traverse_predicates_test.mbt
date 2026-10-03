///|
fn heterogeneous_traversal_graph() -> @carrier.Carrier {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let text = @contract.primitive(@contract.StringType, nullable=false)
  let nullable_text = @contract.primitive(@contract.StringType, nullable=true)
  let node_a_properties = @carrier.rows(
    [
      (Unqualified("maybe"), Some(nullable_text)),
      (Unqualified("title"), Some(text)),
    ],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let node_b_properties = @carrier.rows(
    [(Unqualified("maybe"), Some(nullable_text))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let edge_a_properties = @carrier.rows(
    [
      (Unqualified("shared"), Some(number)),
      (Unqualified("weight"), Some(number)),
    ],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let edge_b_properties = @carrier.rows(
    [(Unqualified("shared"), Some(number))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let node_a = @carrier.property_node_definition(
    "A",
    [number],
    node_a_properties,
    ["NodeA"],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let node_b = @carrier.property_node_definition(
    "B",
    [number],
    node_b_properties,
    ["NodeB"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let edge_a = @carrier.property_edge_definition(
    @carrier.property_node_definition(
      "EA",
      [number],
      edge_a_properties,
      ["L1"],
      max_fields=2,
      max_name_bytes=100,
    ).unwrap(),
    "A",
    "A",
  ).unwrap()
  let edge_b = @carrier.property_edge_definition(
    @carrier.property_node_definition(
      "EB",
      [number],
      edge_b_properties,
      ["L2"],
      max_fields=1,
      max_name_bytes=100,
    ).unwrap(),
    "B",
    "B",
  ).unwrap()
  @carrier.property_graph(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    [node_a, node_b],
    [edge_a, edge_b],
    max_definitions=4,
    max_contract_work=1000,
  ).unwrap()
}

///|
fn heterogeneous_traversal_body(hop : String) -> @decode.Cursor {
  cursor(
    "{\"start\":{\"ids\":[{\"definition\":\"A\",\"domain\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}]},\"hops\":[{" +
    hop +
    "}],\"path_mode\":\"trail\",\"emit\":\"paths\"}",
  )
}

///|
test "traverse hop predicates require fields on every static candidate" {
  let graph = heterogeneous_traversal_graph()
  for
    hop in [
      "\"direction\":\"out\",\"edge_where\":\"shared > 0\",\"node_where\":\"maybe IS NULL\"",
      "\"direction\":\"out\",\"edge_types\":[\"L1\"],\"edge_where\":\"weight > 0\",\"node_where\":\"title = 'x'\"",
    ] {
    let checked = @graph_typing.check_traverse(
      heterogeneous_traversal_body(hop),
      graph,
      None,
      None,
      predicate_limits(),
    ).unwrap()
    let selected = @graph_typing.traverse_hop_at(checked, 0).unwrap()
    assert_true(@graph_typing.hop_edge_predicate(selected) is Some(_))
    assert_true(@graph_typing.hop_node_predicate(selected) is Some(_))
  }
  for
    hop in [
      "\"direction\":\"out\",\"edge_where\":\"weight > 0\"", "\"direction\":\"out\",\"node_where\":\"title = 'x'\"",
      "\"direction\":\"out\",\"edge_types\":[],\"edge_where\":\"weight > 0\"",
    ] {
    assert_true(
      @graph_typing.check_traverse(
        heterogeneous_traversal_body(hop),
        graph,
        None,
        None,
        predicate_limits(),
      )
      is Err(
        @graph_typing.MatchPredicate(@graph_typing.UnknownPredicateField(_))
      ),
    )
  }
  assert_true(
    @graph_typing.check_traverse(
      heterogeneous_traversal_body(
        "\"direction\":\"out\",\"edge_where\":\"shared = 'x'\"",
      ),
      graph,
      None,
      None,
      predicate_limits(),
    )
    is Err(@graph_typing.MatchPredicate(@graph_typing.TypingIssue(_))),
  )
}
