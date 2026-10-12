///|
test "uppercase traverse hop fields retain an independent checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"node_key":"aql_query_expr_0"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","node_rows":true,"as":"aql_sga_4"},{"from":"aql_sga_4","select":[{"element":"id"}],"as":"aql_script_cte_3"},{"from":"aql_with_graph_2","traverse":{"start":{"from":"aql_script_cte_3","id":"element"},"hops":[{"direction":"out","edge_types":[],"node_where":{"literal":true},"edge_where":{"literal":true}}],"path_mode":"walk","emit":"nodes","max_output_rows":10},"as":"aql_sga_5"},{"from":"aql_sga_5","select":["start_id","node_id","depth"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["start_id","node_id","depth"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed_with_evidence(
      expected,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    _ => fail("the independent Graph/selector Program is closed")
  }
  for
    tail in [
      "traverse(start: {from: seeds, id: 'element'}, hops: [{direction: 'out', edge_types: [], node_where: {literal: true}, edge_where: {literal: true}}], path_mode: 'walk', emit: 'nodes', max_output_rows: 10)",
      "TRAVERSE(START: {FROM: seeds, ID: 'element'}, HOPS: [{DIRECTION: 'out', EDGE_TYPES: [], NODE_WHERE: {literal: true}, EDGE_WHERE: {literal: true}}], PATH_MODE: 'walk', EMIT: 'nodes', MAX_OUTPUT_ROWS: 10)",
      "traverse(start: {from: seeds, id: 'element'}, hops: [{`DiReCtIoN`: 'out', `EdGe_TyPeS`: [], `NoDe_WhErE`: {literal: true}, `EdGe_WhErE`: {literal: true}}], path_mode: 'walk', emit: 'nodes', max_output_rows: 10)",
    ] {
    let actual = compile_with_set(
      traversal_nodes_source() +
      "FROM g |> " +
      tail +
      " |> SELECT start_id, node_id, depth",
    )
    assert_eq(semantic(actual), semantic(expected), msg=tail)
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
      _ => fail("source preserves the checked typed hop contract")
    }
  }
}
