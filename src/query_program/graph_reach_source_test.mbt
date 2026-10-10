///|
test "Reach public DATA and terminal query retain checked selector and Relation continuation" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_data_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","reach":{"start":{"where":"p = 7"},"direction":"out","max_depth":2},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["depth"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["depth"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let terminal = compile_data_set(
    graph_union_prefix() +
    "FROM g |> reach(start: {where: 'p = 7'}, direction: 'out', max_depth: 2) |> SELECT depth",
  )
  assert_eq(semantic(terminal), semantic(expected))
  check_graph_union_source(expected)
  check_graph_union_source(terminal)
  let data = compile_data_set(
    graph_union_prefix() +
    "DATA reached = FROM g |> reach(start: {where: 'p = 7'}, direction: 'out', max_depth: 2); FROM reached |> SELECT depth",
  )
  check_graph_union_source(data)
}

///|
test "Reach finite array DATA checks connected property selectors" {
  let prefix = "DATA n = SELECT node_key, node_key AS seed FROM UNNEST([3, 2, 1]) node_key; DATA e = SELECT 13 AS edge_key, 2 AS src, 3 AS dst UNION ALL SELECT 12 AS edge_key, 1 AS src, 1 AS dst UNION ALL SELECT 11 AS edge_key, 1 AS src, 2 AS dst UNION ALL SELECT 10 AS edge_key, 1 AS src, 2 AS dst; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (seed)) EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES)); "
  for direction in ["out", "in"] {
    let program = compile_data_set(
      prefix +
      "DATA reached = FROM g |> reach(start: {where: 'seed = 1'}, direction: '\{direction}', max_depth: 2); FROM reached |> SELECT depth |> ORDER BY depth |> RESULT reached",
    )
    check_graph_union_source(program)
  }
}

///|
test "Reach refuses malformed finite bounds and nonexistent selector fields before execution" {
  for
    suffix in [
      "FROM g |> reach(start: {where: 'missing = 1'}, direction: 'out', max_depth: 2) |> SELECT depth",
      "FROM g |> reach(start: {where: 'node_key = 1'}, direction: 'out', max_depth: 2) |> SELECT depth",
      "FROM g |> reach(start: {where: 'true'}, direction: 'out', max_depth: 0) |> SELECT depth",
      "FROM g |> reach(start: {where: 'true'}, direction: 'wrong', max_depth: 2) |> SELECT depth",
      "FROM g |> reach(start: {where: 'true'}, direction: 'out', max_depth: 2, extra: true) |> SELECT depth",
    ] {
    let program = compile_data_set(graph_union_prefix() + suffix)
    assert_true(
      @check.check_parsed_with_evidence(
        program,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      )
      is Rejected(_),
      msg=suffix,
    )
  }
}
