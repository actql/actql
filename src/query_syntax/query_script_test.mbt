///|
test "WITH script shares original query and constructor source positions" {
  let text = "--😀\r\nWITH `nodes input` AS (SELECT 1 AS id),\ng AS (GRAPH (NODE TABLES (`nodes input` AS N KEY (id) LABEL Node NO PROPERTIES)))\nFROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id"
  let script = parse_query_script(text, query_limits(), source_path="graph.aql").unwrap()
  let query = script_query(script)
  assert_eq(query_binding_count(query), 2)
  let nodes = query_binding_at(query, 0).unwrap()
  assert_eq(nodes.name, { value: "nodes input", quoted: true, })
  assert_true(nodes.origin is AuthoredWith(_, 13, _))
  let graph = query_binding_at(query, 1).unwrap()
  guard producer_primary(graph.query) is Some(GraphValue(mapping)) else {
    fail("expected pure constructor")
  }
  assert_eq(mapping.nodes[0].producer, [nodes.name])
  let span = @origin.span(
    @origin.range(script_document(script), mapping.start, mapping.end).unwrap(),
  )
  assert_eq(span.source_path, "graph.aql")
  assert_eq(span.start_line, 3)
  assert_eq(span.start_column, 7)
  assert_eq(relation(query), [{ value: "g", quoted: false, }])
  assert_true(graph_query(query) is Some(_))
}

///|
test "WITH bodies reuse SQL Pipe CTE and set expression grammar" {
  for
    body in [
      "SELECT 1 AS id |> WHERE id > 0", "SELECT 1 AS id UNION ALL SELECT 2 AS id",
      "WITH seed AS (SELECT 1 AS id) FROM seed |> SELECT id", "(SELECT 1 AS id |> SELECT id)",
    ] {
    let script = parse_query_script(
      "WITH nodes AS (" + body + ") FROM nodes |> SELECT id",
      query_limits(),
    ).unwrap()
    let query = script_query(script)
    let last = query_binding_at(query, query_binding_count(query) - 1).unwrap()
    assert_eq(last.name, { value: "nodes", quoted: false, })
    assert_true(producer_primary(last.query) is None)
    assert_eq(relation(query), [{ value: "nodes", quoted: false, }])
  }
}

///|
test "WITH rejects duplicate names malformed and retired entry points" {
  for
    text in [
      "WITH n AS (SELECT 1 AS id), `N` AS (SELECT 2 AS id) SELECT 1 AS id", "WITH n AS (SELECT 1 AS id FROM n SELECT id) SELECT id FROM n",
      "WITH n AS (SELECT 1 AS id)", "WITH g AS (PROPERTY GRAPH (NODE TABLES (n KEY (id)))) SELECT 1 AS id",
      "PROGRAM p { STAGE s { STEP n OP values {} } }", "DATA n = SELECT 1 AS id; FROM n |> SELECT id",
      "WITH n AS (SELECT 1 AS id) SELECT 2 AS id; SELECT 3 AS id",
    ] {
    assert_true(parse_query_script(text, query_limits()) is Err(_), msg=text)
  }
  assert_eq(
    starts_query(
      "DATA n = SELECT 1 AS id; SELECT id FROM n",
      query_limits().lexical,
    ),
    Ok(false),
  )
}

///|
test "WITH applies one shared syntax lexical and work budget" {
  let text = "WITH n AS (SELECT 1 AS id), m AS (SELECT 2 AS id) SELECT 3 AS id"
  let baseline = parse_query_script(text, query_limits()).unwrap()
  let work = script_work(baseline)
  assert_true(
    parse_query_script(text, { ..query_limits(), max_work: work, }) is Ok(_),
  )
  assert_true(
    parse_query_script(text, { ..query_limits(), max_work: work - 1, })
    is Err(_),
  )
  assert_true(
    parse_query_script(text, { ..query_limits(), max_cte_count: 1, }) is Err(_),
  )
  assert_true(
    parse_query_script(text, { ..query_limits(), max_syntax_nodes: 1, })
    is Err(_),
  )
  let issue = parse_query_script(
    "WITH n AS (SELECT 1 AS id),\nm AS () SELECT 1 AS id",
    query_limits(),
    source_path="bad.aql",
  ).unwrap_err()
  assert_eq(issue.span.unwrap().source_path, "bad.aql")
  assert_eq(issue.span.unwrap().start_line, 2)
}
