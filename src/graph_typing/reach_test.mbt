///|
test "Reach predicate selection checks every static definition and distinguishes nullable values" {
  let graph = heterogeneous_traversal_graph()
  for
    (predicate, valid) in [
      ("true", true),
      ("maybe IS NULL", true),
      ("title = 'x'", false),
      ("missing = 1", false),
      ("maybe + 1 > 0", false),
    ] {
    let result = @graph_typing.check_reach(
      cursor(
        "{\"start\":{\"where\":\"" +
        predicate +
        "\"},\"direction\":\"both\",\"max_depth\":1}",
      ),
      graph,
      None,
      None,
      predicate_limits(),
    )
    assert_eq(result is Ok(_), valid, msg=predicate)
    if predicate == "title = 'x'" || predicate == "missing = 1" {
      assert_true(
        result is Err(@graph_typing.MatchPredicate(UnknownPredicateField(_))),
      )
    }
  }
}
