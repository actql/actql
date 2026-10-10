///|
fn traversal_join_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.traversal_join","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false}},"rows":[{"node_key":1}]},"as":"n"},{"values":{"schema":{"depth":{"type":"number","nullable":false},"tag":{"type":"number","nullable":false}},"rows":[{"depth":0,"tag":10},{"depth":0,"tag":20}]},"as":"r"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[]},"as":"g"},{"from":"g","node_rows":true,"as":"rows"},{"from":"rows","select":[{"element":"id"}],"as":"seeds"},{"from":"g","traverse":{"start":{"from":"seeds","id":"element"},"direction":"out","min_hops":0,"max_hops":1,"path_mode":"trail","emit":"nodes","max_output_rows":10},"as":"visited"},{"from":"visited","join":{"with":"r","kind":"inner","on":[{"left":"depth","right":"depth"}],"max_output_rows":10,"select":{"depth":"left.depth","tag":"right.tag"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["depth","tag"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Traversal Relation output joins without a separate execution owner" {
  let expected = traversal_join_control()
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
    NeedsInputs(_) => fail("independent traversal JOIN has no Source")
  }
  let source = traversal_nodes_source() +
    "DATA r = SELECT 0 AS depth, 10 AS tag UNION ALL SELECT 0 AS depth, 20 AS tag; FROM g |> traverse(start: {from: seeds, id: 'element'}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'nodes', max_output_rows: 10) |> AS v |> JOIN r AS rr ON v.depth = rr.depth MAX_OUTPUT_ROWS 10 |> SELECT v.depth AS depth, rr.tag AS tag"
  let actual = compile_data_set(source)
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
    NeedsInputs(_) => fail("traversal selector remains an existing producer")
  }
  let body = semantic(actual)
  assert_eq(body.split("\"traverse\":").length(), 2)
  assert_true(body.contains("\"max_output_rows\":10"))
  assert_true(body.contains("\"emit\":\"nodes\""))
  assert_true(body.contains("\"min_hops\":0"))
  assert_true(body.contains("\"max_hops\":1"))
  assert_true(body.contains("\"path_mode\":\"trail\""))
  assert_true(
    body.contains("\"select\":{\"depth\":\"left.depth\",\"tag\":\"right.tag\"}"),
  )
  assert_true(body.contains("\"fields\":[\"depth\",\"tag\"]"))
}

///|
test "Traversal path JOIN uses its own projected schema and rejects node-only fields" {
  let prefix = traversal_nodes_source() +
    "DATA r = SELECT 0 AS depth, 10 AS tag; FROM g |> traverse(start: {from: seeds, id: 'element'}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'paths', max_output_rows: 10)"
  let actual = compile_data_set(
    prefix +
    " |> SELECT hop_count AS level |> AS v |> JOIN r AS rr ON v.level = rr.depth MAX_OUTPUT_ROWS 10 |> SELECT v.level AS depth, rr.tag AS tag",
  )
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
    NeedsInputs(_) => fail("path projection remains an existing producer")
  }
  let script = @query.parse_query_script(
    prefix +
    " |> AS v |> JOIN r AS rr ON v.depth = rr.depth MAX_OUTPUT_ROWS 10 |> SELECT rr.tag",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      script,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}
