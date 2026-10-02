///|
test "unconnected shortest consumer refuses the current definition without issuing output" {
  let graph = current_scope_graph()
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
