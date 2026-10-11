///|
// Full controls are unchanged from the independent pre-cutover Program oracles.
fn p2_sga_checked(program : @program.Program) -> Unit raise {
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
    NeedsInputs(_) => fail("The independent control uses no external source")
  }
}

///|
test "P2 selector identifiers resolve to their own operand and unchanged complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"node_key":"aql_query_expr_0"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","node_rows":true,"as":"aql_sga_4"},{"from":"aql_sga_4","select":[{"element":"id"}],"as":"aql_script_cte_3"},{"from":"aql_with_graph_2","traverse":{"start":{"from":"aql_script_cte_3","id":"element"},"direction":"out","min_hops":0,"max_hops":1,"path_mode":"trail","emit":"nodes","max_output_rows":10},"as":"aql_sga_5"},{"from":"aql_sga_5","select":["start_id","node_id","depth"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["start_id","node_id","depth"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  p2_sga_checked(expected)
  for
    field in [
      "element", "ELEMENT", "seeds.element", "SEEDS.Element", "`element`",
    ] {
    let actual = compile_with_set(
      traversal_nodes_source() +
      "FROM g |> traverse(start: {from: seeds, id: " +
      field +
      "}, direction: 'out', min_hops: 0, max_hops: +1, path_mode: 'trail', emit: 'nodes', max_output_rows: 10) |> SELECT start_id, node_id, depth",
    )
    assert_eq(semantic(actual), semantic(expected))
    p2_sga_checked(actual)
  }
}

///|
test "P2 selector cannot borrow another producer or nonexistent column" {
  for field in ["g.element", "missing.element", "seeds.missing", "missing"] {
    let script = @query.parse_query_script(
      traversal_nodes_source() +
      "FROM g |> traverse(start: {from: seeds, id: " +
      field +
      "}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'nodes', max_output_rows: 10) |> SELECT depth",
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=field,
    )
  }
}

///|
test "P2 MATCH references preserve literal values and the unchanged complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","match_nodes":{"definition":"N","label":"Person","where":{"gt":[{"field":"p"},{"literal":5}]},"fields":["p"]},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["p"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["p"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile_with_set(
    "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p)))) FROM g |> match_nodes(definition: 'N', label: 'Person', where: {gt: [{field: p}, {literal: +5}]}, fields: [p]) |> SELECT p",
  )
  assert_eq(semantic(actual), semantic(expected))
  p2_sga_checked(expected)
  p2_sga_checked(actual)
}
