///|
test "Graph reach lowers one typed start and explicit traversal bounds" {
  let owner = graph_match_owner(
    "[{\"from\":\"g\",\"reach\":{\"start\":2,\"direction\":\"both\",\"max_depth\":3}}]",
  )
  let prepared = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(prepared, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"reach_0\",\"in\":[\"input_0\"],\"op\":\"SGA.reachable\",\"params\":{\"direction\":\"both\",\"max_depth\":3,\"start\":2}}]",
  )
}

///|
test "Graph reach preparation admits its selector before emission" {
  let owner = graph_match_owner(
    "[{\"from\":\"g\",\"reach\":{\"start\":2,\"direction\":\"out\",\"max_depth\":1}}]",
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 1,
      expressions: { ..expression_limits(), max_work: 1, },
    })
    is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 0,
    })
    is Err(
      @lowering_relation.GraphReachFailure(
        0,
        @lowering_relation.GraphReachPreparationLimit
      )
    ),
  )
}
