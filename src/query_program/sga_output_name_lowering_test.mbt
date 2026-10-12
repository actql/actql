///|
test "P2 quoted reserved output name reaches the unchanged common MATCH contract" {
  let source = "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> match_nodes(definition: 'N', bindings: {identity: `SELECT`}, where: {literal: true}, fields: [`SELECT`]) |> SELECT `SELECT`"
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"node_key":"aql_query_expr_0"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","match_nodes":{"definition":"N","bindings":{"identity":"SELECT"},"where":{"literal":true},"fields":["SELECT"]},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["SELECT"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["SELECT"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = p2_sga_compile(source)
  assert_eq(semantic(actual), semantic(expected))
  p2_sga_checked(expected)
  p2_sga_checked(actual)
}

///|
// Authored public fixtures supply the Source and independent JSON control.
// Common admission is distinct from executing their expected Named Result.
test "P2 quoted OutputName public Source and independent JSON are common-checkable" {
  let source = "WITH n AS (SELECT 2 AS node_key UNION ALL SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (node_key)))) FROM g |> match_nodes(definition: 'N', bindings: {identity: `SELECT`}, where: {literal: true}, fields: [node_key, `SELECT`]) |> SELECT node_key, `SELECT` IS NOT NULL AS bound |> ORDER BY node_key |> RESULT matched"
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.sga_quoted_output_name","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false}},"rows":[{"node_key":2},{"node_key":1}]},"as":"n"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"node_key","to":"node_key"}]}}]}],"edges":[]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","bindings":{"identity":"SELECT"},"where":{"literal":true},"fields":["node_key","SELECT"]},"as":"matched"},{"from":"matched","derive":{"bound":{"not":{"is_null":{"field":"SELECT"}}}}},{"select":["node_key","bound"]},{"sort":[{"field":"node_key","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"out":{"from":"ordered","fields":["node_key","bound"]}}}],"results":{"matched":{"from":{"stage":"main","result":"out"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  p2_sga_checked(expected)
  p2_sga_checked(p2_sga_compile(source))
}
