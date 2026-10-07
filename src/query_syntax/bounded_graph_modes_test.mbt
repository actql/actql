///|
test "bounded Graph paths retain authored and default path modes" {
  let modes : Array[(String, GraphPathMode)] = [
    ("WALK", Walk),
    ("", Walk),
    ("TRAIL", Trail),
    ("ACYCLIC", Acyclic),
  ]
  for (mode, expected) in modes {
    let text = "FROM GRAPH g |> MATCH p = " +
      mode +
      " (:Node)-[:R]->{0,2}(:Node) |> SELECT PATH_LENGTH(p) AS depth"
    let pattern = graph_query(parse_query(text, query_limits()).unwrap()).unwrap().pattern.unwrap()
    assert_eq(pattern.mode, expected)
    assert_eq(pattern.edges[0].min_hops, 0L)
    assert_eq(pattern.edges[0].max_hops, 2L)
    assert_eq(pattern.edges[0].label.unwrap().value, "R")
  }
}

///|
test "bounded modes retain unsupported binding and invalid bound diagnostics" {
  for mode in ["WALK", "TRAIL", "ACYCLIC"] {
    for edge in ["-[e:R]->{1,2}", "-[:R]->{2,1}", "-[:R]->{0,0}"] {
      let text = "FROM GRAPH g |> MATCH " +
        mode +
        " (a)" +
        edge +
        "(b) |> SELECT a.id"
      match parse_query(text, query_limits()) {
        Err(issue) =>
          match issue.issue {
            Syntax(message) =>
              assert_true(
                message.has_prefix("GRAPH_PATTERN_UNSUPPORTED_SHAPE:"),
              )
            _ => fail("The refusal must identify the unsupported Graph shape")
          }
        Ok(_) => fail("An unsupported binding or invalid bound must be refused")
      }
    }
  }
}

///|
test "bounded modes retain anonymous edge predicates" {
  for mode in ["WALK", "TRAIL", "ACYCLIC"] {
    for constraint in ["WHERE weight > 10", "{weight: 20}"] {
      let text = "FROM GRAPH g |> MATCH p = " +
        mode +
        " ()-[:R " +
        constraint +
        "]->{0,2}() |> SELECT PATH_LENGTH(p)"
      let pattern = graph_query(parse_query(text, query_limits()).unwrap()).unwrap().pattern.unwrap()
      assert_true(pattern.edges[0].constraint is Some(_))
      assert_eq(pattern.edges[0].min_hops, 0L)
      assert_eq(pattern.edges[0].max_hops, 2L)
    }
  }
}
