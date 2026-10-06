///|
test "DATA script shares original query and constructor source positions" {
  let text = "--😀\r\nDATA `nodes input` = SELECT 1 AS id;\nDATA g = PROPERTY GRAPH (NODE TABLES (`nodes input` AS N KEY (id) LABEL Node NO PROPERTIES));\nFROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id"
  let script = parse_query_script(text, query_limits(), source_path="graph.aql").unwrap()
  assert_eq(data_declaration_count(script), 2)
  let nodes = data_declaration_at(script, 0).unwrap()
  assert_eq(nodes.name, { value: "nodes input", quoted: true, })
  assert_eq(nodes.start, 8)
  assert_true(nodes.value is RelationQuery(_))
  let graph = data_declaration_at(script, 1).unwrap()
  match graph.value {
    Graph(mapping) => {
      assert_eq(mapping.nodes[0].producer, [nodes.name])
      let span = @origin.span(
        @origin.range(script_document(script), mapping.start, mapping.end).unwrap(),
      )
      assert_eq(span.source_path, "graph.aql")
      assert_eq(span.start_line, 3)
      assert_eq(span.start_column, 10)
    }
    _ => fail("expected pure constructor")
  }
  assert_eq(relation(script_query(script)), [{ value: "g", quoted: false, }])
  assert_true(graph_query(script_query(script)) is Some(_))
}

///|
test "DATA query bodies reuse SQL Pipe CTE and set expression grammar" {
  for
    body in [
      "SELECT 1 AS id |> WHERE id > 0", "SELECT 1 AS id UNION ALL SELECT 2 AS id",
      "WITH seed AS (SELECT 1 AS id) FROM seed |> SELECT id", "(SELECT 1 AS id |> SELECT id)",
    ] {
    let script = parse_query_script(
      "DATA nodes = " + body + "; FROM nodes |> SELECT id",
      query_limits(),
    ).unwrap()
    assert_true(
      data_declaration_at(script, 0).unwrap().value is RelationQuery(_),
    )
    assert_eq(relation(script_query(script)), [
      { value: "nodes", quoted: false, },
    ])
  }
}

///|
test "DATA script rejects duplicate names malformed and legacy entry points" {
  for
    text in [
      "DATA n = SELECT 1 AS id; DATA `N` = SELECT 2 AS id; SELECT 1 AS id", "DATA n = SELECT 1 AS id FROM n SELECT id",
      "DATA n = SELECT 1 AS id;", "DATA n = SELECT 1 AS id; DATA g = graph(nodes: n); SELECT 1 AS id",
      "PROGRAM p { STAGE s { STEP n OP values {} } }", "DATA n = SELECT 1 AS id; SELECT 2 AS id; SELECT 3 AS id",
    ] {
    assert_true(parse_query_script(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "DATA script applies one shared syntax lexical and work budget" {
  let text = "DATA n = SELECT 1 AS id; DATA m = SELECT 2 AS id; SELECT 3 AS id"
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
    "DATA n = SELECT 1 AS id;\nDATA m = ; SELECT 1 AS id",
    query_limits(),
    source_path="bad.aql",
  ).unwrap_err()
  let span = issue.span.unwrap()
  assert_eq(span.source_path, "bad.aql")
  assert_eq(span.start_line, 2)
}
