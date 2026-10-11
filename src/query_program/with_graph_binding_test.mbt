///|
// Full expected Program follows the existing producer naming/order contract.
// It is authored before executing the new WITH lowerer, not copied from output.
test "WITH Graph MATCH reuses its existing owner and complete Program" {
  let actual = compile_data_set(
    "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)))), chosen AS (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value) FROM chosen |> ORDER BY value",
  )
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","match_nodes":{"definition":"N","label":"Node","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_1"},"fields":["aql_keyed_identity_1","p"]},"as":"aql_keyed_seeds_4"},{"from":"aql_keyed_seeds_4","select":[{"value":"p"}],"as":"aql_script_cte_3"},{"from":"aql_script_cte_3","sort":[{"field":"value","dir":"asc","nulls":"first"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  match
    @check.check_parsed_with_evidence(
      actual,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("inline WITH requires no provider")
  }
}

///|
test "WITH Graph binding keeps nearest Carrier and constructor origin" {
  let prefix = "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)))) "
  let parsed = @query.parse_query_script(
    prefix +
    "FROM (WITH g AS (SELECT 2 AS node_key) FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p)",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      parsed,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(_),
  )
  // A nearer Relation cannot be repaired by searching the outer Graph.
}
