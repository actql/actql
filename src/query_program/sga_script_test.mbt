///|
test "SGA DATA normalize lowers once and retains the existing Graph producer" {
  // This is an independently authored ordinary Program. Its only additional
  // step is the existing normalize_graph operation: no Values copy, Result
  // boundary, separate task, source acquisition or local-placement request.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"id","to":"id"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","normalize_graph":true,"as":"aql_sga_4"},{"from":"aql_sga_4","match_nodes":{"definition":"N","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_1"},"fields":["aql_keyed_identity_1","id"],"label":"Node"},"as":"aql_keyed_seeds_5"},{"from":"aql_keyed_seeds_5","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let source = "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); DATA normalized = FROM g |> normalize_graph(); FROM GRAPH normalized |> MATCH WALK (a:Node) |> SELECT a.id"
  let actual = compile_data_set(source)
  assert_eq(semantic(actual), semantic(expected))
  assert_eq(@program.stage_count(actual), 1)
  assert_eq(@program.export_count(actual), 1)
  // Lowering evidence only: common-owner admission and public execution
  // are deliberately tested at separate boundaries after the formal handoff.
}

///|
test "SGA normalize can precede MATCH without a synthesized DATA or Result" {
  let source = "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); FROM GRAPH g |> normalize_graph() |> MATCH WALK (a:Node) |> SELECT a.id"
  let actual = semantic(compile_data_set(source))
  assert_true(actual.contains("\"normalize_graph\":true"))
  assert_true(actual.contains("\"as\":\"aql_sga_3\""))
  assert_true(actual.contains("\"from\":\"aql_sga_3\""))
  assert_false(actual.contains("aql_retained_result"))
}

///|
test "SGA graph alias reuse never introduces a Values copy or reacquisition" {
  let source = "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); DATA copied = FROM g; FROM GRAPH copied |> MATCH WALK (a:Node) |> SELECT a.id"
  let actual = semantic(compile_data_set(source))
  assert_true(actual.contains("\"from\":\"aql_data_2\",\"match_nodes\""))
  assert_false(actual.contains("normalize_graph"))
  assert_eq(@program.export_count(compile_data_set(source)), 1)
}

///|
test "SGA script rejects unknown references unconnected consumers and extra input arguments" {
  let prefix = "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); "
  for
    suffix in [
      "DATA normalized = FROM g |> normalize_graph(with: 'g'); FROM GRAPH normalized |> MATCH WALK (a:Node) |> SELECT a.id",
      "DATA normalized = FROM g |> normalize_graph(extra: true); FROM GRAPH normalized |> MATCH WALK (a:Node) |> SELECT a.id",
      "DATA combined = mean_graphs(with: [g, g]); FROM GRAPH combined |> MATCH WALK (a:Node) |> SELECT a.id",
      "DATA normalized = FROM g |> normalize_graph() |> SELECT id; FROM normalized |> SELECT id",
      "FROM n |> normalize_graph() |> SELECT id",
    ] {
    let script = match
      @query.parse_query_script(prefix + suffix, syntax_limits()) {
      Ok(script) => script
      Err(issue) => fail(suffix + " : " + @debug.to_string(issue.issue))
    }
    assert_true(
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnsupportedGraph),
      msg=suffix,
    )
  }
  let unknown = @query.parse_query_script(
    prefix +
    "DATA normalized = FROM later |> normalize_graph(); FROM GRAPH normalized |> MATCH WALK (a:Node) |> SELECT a.id",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      unknown,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(UnknownRelation),
  )
}
