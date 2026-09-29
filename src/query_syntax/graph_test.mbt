///|
test "Graph MATCH retains source labels, mode and directed occurrences" {
  let query = parse_query(
    "FROM GRAPH crm_graph LABELS {\"node\":{\"field\":\"entity_type\"}} |> MATCH ACYCLIC (a:Account)-[e:HAS_CONTACT]->(b:Contact) |> SELECT a.name AS account_name;",
    query_limits(),
  ).unwrap()
  assert_eq(relation(query), [{ value: "crm_graph", quoted: false, }])
  let graph = graph_query(query).unwrap()
  assert_eq(graph.label_field, Some("entity_type"))
  let pattern = graph.pattern.unwrap()
  assert_eq(pattern.mode, Acyclic)
  assert_eq(pattern.nodes.length(), 2)
  assert_eq(pattern.edges.length(), 1)
  assert_eq(pattern.nodes[0].variable.unwrap().value, "a")
  assert_eq(pattern.nodes[0].label.unwrap().value, "Account")
  assert_eq(pattern.edges[0].variable.unwrap().value, "e")
  assert_eq(pattern.edges[0].label.unwrap().value, "HAS_CONTACT")
  assert_eq(pattern.edges[0].direction, "out")
  assert_eq(pattern.nodes[1].label.unwrap().value, "Contact")
  assert_eq(operation_count(query), 1)
}

///|
test "Graph MATCH retains bounded path and local property expressions" {
  let query = parse_query(
    "FROM GRAPH g |> MATCH p = ACYCLIC (a {id: 'missing'})-[:R]->{1,2}(b) |> SELECT b.id;",
    query_limits(),
  ).unwrap()
  let pattern = graph_query(query).unwrap().pattern.unwrap()
  assert_eq(pattern.path_name.unwrap().value, "p")
  assert_eq(pattern.edges[0].min_hops, 1L)
  assert_eq(pattern.edges[0].max_hops, 2L)
  assert_true(pattern.edges[0].quantified)
  assert_true(pattern.nodes[0].constraint is Some(Properties(_)))
  assert_true(pattern.edges[0].constraint is None)
}

///|
test "Graph WHERE starts anonymous constraints but quoted WHERE remains a name" {
  for
    (text, edge) in [
      ("FROM GRAPH g |> MATCH WALK (WHERE id = 1) |> SELECT id", false),
      (
        "FROM GRAPH g |> MATCH WALK (a)-[WHERE src = 1]->(b) |> SELECT b.id", true,
      ),
    ] {
    let pattern = graph_query(parse_query(text, query_limits()).unwrap()).unwrap().pattern.unwrap()
    if edge {
      assert_true(pattern.edges[0].variable is None)
      assert_true(pattern.edges[0].constraint is Some(Predicate(_)))
    } else {
      assert_true(pattern.nodes[0].variable is None)
      assert_true(pattern.nodes[0].constraint is Some(Predicate(_)))
    }
  }
  let named = graph_query(
    parse_query(
      "FROM GRAPH g |> MATCH WALK (`WHERE` WHERE id = 1)-[`WHERE` WHERE src = 1]->(b) |> SELECT `WHERE`.id",
      query_limits(),
    ).unwrap(),
  ).unwrap().pattern.unwrap()
  assert_true(named.nodes[0].variable.unwrap().quoted)
  assert_eq(named.nodes[0].variable.unwrap().value, "WHERE")
  assert_true(named.edges[0].variable.unwrap().quoted)
  assert_eq(named.edges[0].variable.unwrap().value, "WHERE")
}

///|
test "Graph MATCH rejects open, repeated and unowned patterns" {
  for
    text in [
      "FROM GRAPH g |> MATCH ACYCLIC (a)-[:R]->+(b) |> SELECT a.id", "FROM GRAPH g |> MATCH ACYCLIC (a)-[:R]->{1,}(b) |> SELECT a.id",
      "FROM GRAPH g |> MATCH ACYCLIC (a)-[:R]->{1,1}(b)-[:R]->(c) |> SELECT a.id",
      "FROM GRAPH g |> MATCH ACYCLIC (a)-[e:R]->{1,2}(b) |> SELECT a.id", "FROM GRAPH g |> MATCH WALK (a)-[:R]->{1,2}(b) |> SELECT a.id",
      "FROM GRAPH g |> MATCH (a) |> SELECT a.id", "FROM GRAPH g |> MATCH WALK (a) |> MATCH WALK (b) |> SELECT a.id",
      "FROM GRAPH g |> MATCH WALK (a:Account) |> SELECT a.id", "FROM rows |> MATCH WALK (a) |> SELECT a.id",
      "FROM GRAPH g |> SELECT id",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "Graph MATCH uses the shared bounded query budget" {
  let text = "FROM GRAPH g |> MATCH WALK (a)-[:R]->(b) |> SELECT a.id"
  assert_true(
    parse_query(text, { ..query_limits(), max_syntax_nodes: 1, }) is Err(_),
  )
  assert_true(
    parse_query(text, {
      ..query_limits(),
      lexical: { ..limits(), max_tokens: 9, },
    })
    is Err(_),
  )
}

///|
test "Graph JSON strings do not become SQL expression strings" {
  assert_true(parse_query("SELECT \"id\" FROM rows", query_limits()) is Err(_))
}
