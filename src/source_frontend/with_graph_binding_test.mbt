///|
// Both public text selectors consume the same authored binding/Graph source.
// The complete machine control is independently written from producer roles.
test "WITH Graph shared SQL and text route matches independent Program" {
  let source = "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)))), chosen AS (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value) FROM chosen |> ORDER BY value"
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"frontend.route","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","match_nodes":{"definition":"N","label":"Node","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_1"},"fields":["aql_keyed_identity_1","p"]},"as":"aql_keyed_seeds_4"},{"from":"aql_keyed_seeds_4","select":[{"value":"p"}],"as":"aql_script_cte_3"},{"from":"aql_script_cte_3","sort":[{"field":"value","dir":"asc","nulls":"first"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    {
      source: { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
      tree: { max_nodes: 8192, max_depth: 64, max_string_bytes: 65536, max_total_string_bytes: 65536, },
      max_stages: 32,
    },
    format=Json,
  ).unwrap()
  let writer = @encode.writer(65536, 8192, 64)
  @program.emit_program_source(expected, writer)
  let expected_text = @encode.finish(writer)
  for format in [Text, Sql] {
    let actual = lower(source, format, Some(context), source_path="bindings.sql").unwrap()
    assert_eq(actual.format, @program.Json)
    assert_eq(actual.document, expected_text)
    let program = actual.program.unwrap()
    let steps = @wire.elements(lookup(@program.stage_body(@program.stages(program)[0]), "steps")).unwrap()
    let span = @wire.cursor_span(lookup(steps[3], "graph"))
    assert_eq(span.source_path, "bindings.sql")
    assert_eq(span.start_byte, 48)
    assert_eq(span.end_byte, 117)
  }
}

///|
test "public WITH cutover rejects retired DATA without structural fallback" {
  for format in [Text, Sql] {
    assert_true(lower("DATA n = SELECT 1 AS id; SELECT id FROM n", format, Some(test_context())) is Err(WrongQueryForm))
    assert_true(lower("WITH g AS (PROPERTY GRAPH (NODE TABLES (records KEY (id)))) SELECT 1 AS id", format, Some(test_context())) is Err(QuerySyntax(_)))
  }
}
