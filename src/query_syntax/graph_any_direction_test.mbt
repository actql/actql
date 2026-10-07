///|
test "any-direction Graph edges retain direction bounds and path modes" {
  for mode in ["WALK", "TRAIL", "ACYCLIC", ""] {
    let query = parse_query(
      "FROM GRAPH g |> MATCH p = " +
      mode +
      " (a)-[:R]-(b)<-[]-(c)-[]->(d) |> SELECT PATH_LENGTH(p) AS depth",
      query_limits(),
    ).unwrap()
    let pattern = graph_query(query).unwrap().pattern.unwrap()
    assert_eq(pattern.edges.map(edge => edge.direction), ["both", "in", "out"])
    assert_eq(pattern.edges[0].min_hops, 1L)
    assert_eq(pattern.edges[0].max_hops, 1L)
    assert_false(pattern.edges[0].quantified)
    assert_eq(pattern.edges[2].min_hops, 1L)
    assert_eq(pattern.edges[2].max_hops, 1L)
    assert_false(pattern.edges[2].quantified)
  }
}

///|
test "any-direction Graph quantifier retains an anonymous predicate" {
  let query = parse_query(
    "FROM GRAPH g |> MATCH p = TRAIL (a)-[WHERE cost > 0]-{0,2}(b) |> SELECT PATH_LENGTH(p) AS depth",
    query_limits(),
  ).unwrap()
  let edge = graph_query(query).unwrap().pattern.unwrap().edges[0]
  assert_eq(edge.direction, "both")
  assert_eq(edge.min_hops, 0L)
  assert_eq(edge.max_hops, 2L)
  assert_true(edge.constraint is Some(Predicate(_)))
}

///|
test "any-direction edges do not admit malformed arrows or open quantifiers" {
  for
    edge in ["<-[]->", "-[]-*", "-[]-+", "-[]-{1,}", "-[]-{2,1}", "-[e]-{0,2}"] {
    assert_true(
      parse_query(
        "FROM GRAPH g |> MATCH p = WALK (a)" +
        edge +
        "(b) |> SELECT PATH_LENGTH(p) AS depth",
        query_limits(),
      )
      is Err(_),
      msg=edge,
    )
  }
}
