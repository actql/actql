///|
fn traversal_nodes_source() -> String {
  "DATA n = SELECT 1 AS node_key; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES)); DATA seeds = FROM g |> node_rows() |> SELECT id AS element; "
}

///|
test "Graph traversal node source retains an independent complete Program" {
  let actual = compile_data_set(
    traversal_nodes_source() +
    "FROM g |> traverse(start: {from: seeds, id: 'element'}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'nodes', max_output_rows: 10) |> SELECT start_id, node_id, depth",
  )
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"node_key":"aql_query_expr_0"}],"as":"aql_data_0"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","node_rows":true,"as":"aql_sga_4"},{"from":"aql_sga_4","select":[{"element":"id"}],"as":"aql_data_3"},{"from":"aql_data_2","traverse":{"start":{"from":"aql_data_3","id":"element"},"direction":"out","min_hops":0,"max_hops":1,"path_mode":"trail","emit":"nodes","max_output_rows":10},"as":"aql_sga_5"},{"from":"aql_sga_5","select":["start_id","node_id","depth"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["start_id","node_id","depth"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    NeedsInputs(_) => fail("A DATA traversal selector does not acquire inputs")
  }
}

///|
test "Graph traversal node output continues as a Relation DATA producer" {
  let actual = compile_data_set(
    traversal_nodes_source().replace(old="seeds", new="`seed set`") +
    "DATA visited = FROM g |> traverse(start: {from: `seed set`, id: 'element'}, hops: [{direction: 'out', edge_types: []}], path_mode: 'walk', emit: 'nodes') |> SELECT depth; FROM visited |> WHERE depth > 0 |> ORDER BY depth",
  )
  let body = semantic(actual)
  assert_true(
    body.contains("\"hops\":[{\"direction\":\"out\",\"edge_types\":[]}]"),
  )
  assert_true(body.contains("\"path_mode\":\"walk\""))
  assert_eq(body.split("\"traverse\":").length(), 2)
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
    NeedsInputs(_) => fail("Traversal DATA remains a shared producer")
  }
}

///|
test "Graph traversal retains malformed authored bodies for common refusal" {
  for
    tail in [
      "traverse(start: {from: seeds, id: 'element'}, direction: 'out', min_hops: 0, max_hops: 0, path_mode: 'trail', emit: 'nodes')",
      "traverse(start: {from: seeds, id: 'element'}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'invented', emit: 'nodes')",
      "traverse(start: {from: seeds, id: 'missing'}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'nodes')",
      "traverse(start: {from: seeds, id: 'element'}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'nodes', extra: true)",
    ] {
    let actual = compile_data_set(
      traversal_nodes_source() + "FROM g |> " + tail + " |> SELECT depth",
    )
    assert_true(
      @check.check_parsed_with_evidence(
        actual,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      )
      is Rejected(_),
      msg=tail,
    )
  }
  for
    tail in [
      "traverse(start: {from: undeclared, id: 'element'}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'nodes')",
      "traverse(start: {from: seeds, id: 'element'}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'paths')",
    ] {
    let parsed = @query.parse_query_script(
      traversal_nodes_source() + "FROM g |> " + tail,
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
  }
}
