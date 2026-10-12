///|
test "Shortest WITH and terminal query share the authored Program and common admission" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","shortest_path":{"source":{"where":"p = 7"},"target":{"where":"p = 7"},"selection":"each_pair","direction":"out","max_hops":2},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["hop_count","total_cost"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["hop_count","total_cost"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let call = "FROM g |> shortest_path(source: {where: 'p = 7'}, target: {where: 'p = 7'}, selection: 'each_pair', direction: 'out', max_hops: 2)"
  let terminal = compile_with_set(
    graph_union_prefix() + call + " |> SELECT hop_count, total_cost",
  )
  assert_eq(semantic(terminal), semantic(expected))
  check_graph_union_source(expected)
  check_graph_union_source(terminal)
  check_graph_union_source(
    compile_with_set(
      graph_union_prefix() +
      ", paths AS (" +
      call +
      ") FROM paths |> SELECT hop_count, total_cost",
    ),
  )
}

///|
test "Shortest public checking refuses invalid hops selectors direction and weight" {
  for
    body in [
      "source: {where: 'true'}, target: {where: 'true'}, selection: 'each_pair', direction: 'out', max_hops: 0",
      "source: {where: 'missing = 1'}, target: {where: 'true'}, selection: 'each_pair', direction: 'out', max_hops: 1",
      "source: {where: 'node_key = 1'}, target: {where: 'true'}, selection: 'each_pair', direction: 'out', max_hops: 1",
      "source: {where: 'true'}, target: {where: 'true'}, direction: 'out', max_hops: 1",
      "source: {where: 'true'}, target: {where: 'true'}, selection: 'each_pair', direction: 'wrong', max_hops: 1",
      "source: {where: 'true'}, target: {where: 'true'}, selection: 'each_pair', direction: 'out', max_hops: 1, weight: `missing`",
    ] {
    expect_with_graph_static_refusal(
      graph_union_prefix() +
      "FROM g |> shortest_path(" +
      body +
      ") |> SELECT hop_count",
    )
  }
}
