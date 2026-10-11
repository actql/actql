///|
test "Shortest indexed obligations preserve original order and optional guard binding" {
  let parameters = @parameter.read_declarations(
    Some(cursor("{\"limit\":{\"type\":\"number\"}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let cases : Array[(String, @graph_typing.ShortestObligation?)] = [
    ("", None),
    (",\"max_output_rows\":10", Some(EnforceShortestOutputGuard)),
    (
      ",\"max_output_rows\":{\"$param\":\"limit\"}",
      Some(BindShortestOutputGuard("limit")),
    ),
  ]
  for (options, last) in cases {
    let checked = @graph_typing.check_shortest(
      cursor(
        shortest_body(
          current_node_identity(2),
          current_node_identity(10),
          options,
        ),
      ),
      current_scope_graph(),
      None,
      None,
      Some(parameters),
      predicate_limits(),
    ).unwrap()
    let expected : Array[@graph_typing.ShortestObligation] = [
      AdmitShortestGraph,
      AdmitShortestSelectors,
      DeduplicateShortestSelectors,
      RequireShortestMembership,
      ValidateEveryShortestWeight,
      RespectShortestHopBound,
      EnumerateSimpleShortestPaths,
      SelectCanonicalShortestPaths,
      RejectSelectedOverrange,
      CanonicalShortestOutputOrder,
      ResolveShortestResources,
      ResolveShortestProfile,
    ]
    if last is Some(item) {
      expected.push(item)
    }
    assert_eq(@graph_typing.shortest_pending(checked), expected)
    assert_eq(@graph_typing.shortest_pending_count(checked), expected.length())
    let traversal = @graph_typing.shortest_traversal(checked)
    for index in 0..<expected.length() {
      assert_eq(
        @graph_typing.shortest_pending_at(checked, index),
        Some(expected[index]),
      )
      assert_eq(
        @graph_typing.traverse_pending_at(traversal, index),
        Some(ShortestRequirement(expected[index])),
      )
    }
    for
      index in [
        -2147483648,
        -1,
        expected.length(),
        expected.length() + 1,
        2147483647,
      ] {
      assert_eq(@graph_typing.shortest_pending_at(checked, index), None)
    }
  }
}
