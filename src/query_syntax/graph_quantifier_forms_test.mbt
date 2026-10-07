///|
test "finite Graph quantifier spellings preserve explicit and omitted bounds" {
  for
    (bounds, minimum, maximum) in [
      ("{2}", 2L, 2L),
      ("{,2}", 0L, 2L),
      ("{1,2}", 1L, 2L),
    ] {
    for edge in ["-[]->", "<-[]-", "-[]-", "->", "<-", "-"] {
      let query = parse_query(
        "FROM GRAPH g |> MATCH p = TRAIL (a)" +
        edge +
        bounds +
        "(b) |> SELECT PATH_LENGTH(p) AS depth",
        query_limits(),
      ).unwrap()
      let actual = graph_query(query).unwrap().pattern.unwrap().edges[0]
      assert_true(actual.quantified)
      assert_eq(actual.min_hops, minimum)
      assert_eq(actual.max_hops, maximum)
      assert_true(actual.variable is None)
    }
  }
}

///|
test "finite Graph quantifiers retain rejection of invalid bounds and named groups" {
  for
    edge in [
      "-[]->{0}", "-[]->{,0}", "-[]->{2,1}", "-[]->{1,}", "-[]->{}", "-[]->{-1}",
      "-[]->{1.5}", "-[]->{9007199254740992}", "-[e]->{2}", "-[e]->{,2}",
    ] {
    assert_true(
      parse_query(
        "FROM GRAPH g |> MATCH (a)" + edge + "(b) |> SELECT a.id",
        query_limits(),
      )
      is Err(_),
      msg=edge,
    )
  }
}
