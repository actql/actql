///|
test "unconnected structural consumers reject the current definition domain without issuing outputs" {
  let graph = current_scope_graph()
  guard graph is @carrier.GraphValue(value) else { fail("Graph") }
  let contract = @graph_contract.admit_graph(value, {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  let pair = cursor("{\"with\":\"peer\"}")
  let results : Array[Result[Unit, @graph_typing.Issue]] = [
    @graph_typing.check_diff(pair, graph, graph, limits()).map(_ => ()),
    @graph_typing.check_union(pair, graph, [graph], limits()).map(_ => ()),
    @graph_typing.check_equality(pair, graph, graph, limits()).map(_ => ()),
    @graph_typing.check_apply(
      cursor("{\"with\":\"delta\",\"field\":\"delta\"}"),
      graph,
      @carrier.relation(@carrier.unknown_rows()),
      contract,
      limits(),
    ).map(_ => ()),
  ]
  for result in results {
    assert_true(result is Err({ kind: UnsupportedGraphOperation, .. }))
  }
  for
    operation in [
      @graph_typing.Union,
      @graph_typing.Subtract,
      @graph_typing.Graft,
    ] {
    assert_true(
      @graph_typing.check_structural(operation, pair, graph, graph, limits())
      is Err({ kind: UnsupportedGraphOperation, .. }),
    )
  }
  assert_true(
    @graph_typing.check_shortest(
      cursor("{}"),
      graph,
      None,
      None,
      None,
      predicate_limits(),
    )
    is Err(
      @graph_typing.MatchStructure({ kind: UnsupportedGraphOperation, .. })
    ),
  )
}
