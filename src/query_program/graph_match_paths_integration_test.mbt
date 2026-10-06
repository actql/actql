///|
fn matched_traversal_path_source() -> String {
  traversal_paths_source().replace(
    old="node_rows()",
    new="match_nodes(definition: 'N', bindings: {identity: 'id'}, where: {literal: true}, fields: ['id'])",
  )
}

///|
test "named Graph match feeds traversal paths in one checked source Program" {
  let actual = compile_data_set(matched_traversal_path_source())
  // The existing independent path Program with an explicitly authored match
  // step supplies the oracle; compiler output does not supply expectations.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"node_key":"aql_query_expr_0"}],"as":"aql_data_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","match_nodes":{"definition":"N","bindings":{"identity":"id"},"where":{"literal":true},"fields":["id"]},"as":"aql_sga_4"},{"from":"aql_sga_4","select":[{"element":"id"}],"as":"aql_data_3"},{"from":"aql_data_2","traverse":{"start":{"from":"aql_data_3","id":"element"},"direction":"out","min_hops":0,"max_hops":1,"path_mode":"trail","emit":"paths","max_output_rows":10},"as":"aql_sga_5"},{"from":"aql_sga_5","select":["start_id","end_id","hop_count","node_ids","edge_ids"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["start_id","end_id","hop_count","node_ids","edge_ids"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  for program in [expected, actual] {
    match
      @check.check_parsed_with_evidence(
        program,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) => fail("The matched selector reuses the same Graph")
    }
  }
}

///|
test "combined match and path source preserves independent refusal boundaries" {
  let missing_selector = compile_data_set(
    matched_traversal_path_source().replace(
      old="id: 'element'",
      new="id: 'missing'",
    ),
  )
  assert_true(
    @check.check_parsed_with_evidence(
      missing_selector,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    )
    is Rejected(_),
  )
  let node_only_field = matched_traversal_path_source().replace(
    old="SELECT start_id, end_id, hop_count, node_ids, edge_ids",
    new="SELECT depth",
  )
  assert_true(
    compile_query_script(
      @query.parse_query_script(node_only_field, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}
