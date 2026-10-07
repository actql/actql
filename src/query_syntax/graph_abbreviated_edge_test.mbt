///|
test "abbreviated Graph edges preserve direction and have no filler" {
  for (edge, direction) in [("-", "both"), ("<-", "in"), ("->", "out")] {
    let source = "FROM GRAPH g |> MATCH p = (a)" +
      edge +
      "(`b`) |> SELECT PATH_LENGTH(p) AS depth"
    let pattern = graph_query(parse_query(source, query_limits()).unwrap()).unwrap().pattern.unwrap()
    let actual = pattern.edges[0]
    assert_eq(actual.direction, direction)
    assert_eq(actual.variable, None)
    assert_eq(actual.label, None)
    assert_true(actual.constraint is None)
    assert_eq(actual.min_hops, 1L)
    assert_eq(actual.max_hops, 1L)
    assert_false(actual.quantified)
    assert_eq(actual.end - actual.start, edge.length())
    assert_true(pattern.mode is Walk)
  }
}

///|
test "abbreviated Graph edges share bounded quantifiers and explicit path modes" {
  for mode in ["WALK", "TRAIL", "ACYCLIC"] {
    for (edge, direction) in [("-", "both"), ("<-", "in"), ("->", "out")] {
      let source = "FROM GRAPH g |> MATCH p = " +
        mode +
        " (a)" +
        edge +
        "{0,2}(b) |> SELECT PATH_LENGTH(p) AS depth"
      let pattern = graph_query(parse_query(source, query_limits()).unwrap()).unwrap().pattern.unwrap()
      let actual = pattern.edges[0]
      assert_eq(actual.direction, direction)
      assert_true(actual.quantified)
      assert_eq(actual.min_hops, 0L)
      assert_eq(actual.max_hops, 2L)
    }
  }
}

///|
test "mixed full and abbreviated fixed hops retain authored node scopes" {
  let query = parse_query(
    "FROM GRAPH g |> MATCH p = TRAIL (a)-(`b` WHERE b.id = 2)<-[:R]-(c)->(d) |> SELECT PATH_LENGTH(p) AS depth",
    query_limits(),
  ).unwrap()
  let pattern = graph_query(query).unwrap().pattern.unwrap()
  assert_eq(pattern.edges.map(edge => edge.direction), ["both", "in", "out"])
  assert_eq(pattern.edges[0].label, None)
  assert_true(pattern.edges[1].label is Some(_))
  assert_true(pattern.nodes[1].constraint is Some(Predicate(_)))
  assert_true(pattern.mode is Trail)
}

///|
test "abbreviated Graph arrows do not consume malformed fillers or SQL comments" {
  for
    edge in ["<->", "->>", "<-<", "-:R", "-[", "-*", "->+", "<-{1,}", "-{2,1}"] {
    assert_true(
      parse_query(
        "FROM GRAPH g |> MATCH (a)" + edge + "(b) |> SELECT a.id",
        query_limits(),
      )
      is Err(_),
      msg=edge,
    )
  }
  let comment = parse_query(
    "FROM GRAPH g |> MATCH (a)--(b)\n|> SELECT a.id",
    query_limits(),
  ).unwrap()
  assert_eq(graph_query(comment).unwrap().pattern.unwrap().edges.length(), 0)
}
