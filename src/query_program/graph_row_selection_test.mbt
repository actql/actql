///|
test "Graph definition selector has an independent complete Program" {
  let actual = compile_data_set(
    "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); FROM g |> node_rows(definition: 'n') |> SELECT p, node_key",
  )
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_data_0"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","node_rows":{"definition":"n"},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["p","node_key"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["p","node_key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "Graph selectors preserve declared fields and common checking" {
  let prefix = "DATA n = SELECT 1 AS node_key, CAST(NULL AS FLOAT64) AS p; DATA m = SELECT 2 AS other_key; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p), m AS M KEY (other_key) LABEL Company NO PROPERTIES)); "
  for
    suffix in [
      "FROM g |> node_rows(definition: 'n') |> SELECT node_key, p, labels", "FROM g |> node_rows(label: 'PERSON') |> SELECT node_key, p, labels",
      "DATA rows = FROM g |> node_rows(label: 'Company') |> SELECT other_key; FROM rows |> ORDER BY other_key",
    ] {
    let program = compile_data_set(prefix + suffix)
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
      NeedsInputs(_) => fail("Graph selection adds no acquisition")
    }
  }
  for
    suffix in [
      "FROM g |> node_rows(label: 'Person') |> SELECT other_key", "FROM g |> node_rows(definition: 'unknown') |> SELECT id",
      "FROM g |> node_rows(definition: 'N', label: 'Person') |> SELECT id", "FROM g |> node_rows(label: 1) |> SELECT id",
    ] {
    let script = @query.parse_query_script(prefix + suffix, syntax_limits()).unwrap()
    assert_true(
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(_),
      msg=suffix,
    )
  }
}

///|
test "Graph label selection does not invent Conditional presence" {
  let prefix = "DATA n = SELECT 1 AS key, 7 AS p, 8 AS q; DATA m = SELECT 2 AS key, 9 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (key) LABEL Person PROPERTIES (p) LABEL Owner PROPERTIES (q), m AS M KEY (key) LABEL Person PROPERTIES (p))); "
  // The selected label chooses definitions, not just its own properties.
  // q exists on N but remains Conditional across N and M.
  for
    suffix in [
      "FROM g |> node_rows(label: 'Person') |> SELECT q", "FROM g |> node_rows(label: 'Person') |> WHERE q IS NOT NULL |> SELECT key",
    ] {
    let program = compile_data_set(prefix + suffix)
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
  let program = compile_data_set(
    prefix +
    "FROM g |> node_rows(label: 'Person') |> SELECT key, p |> WHERE p > 0 |> ORDER BY key",
  )
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
    NeedsInputs(_) => fail("Graph label selection adds no acquisition")
  }
}

///|
test "Graph quoted element names remain string selectors" {
  let program = compile_data_set(
    "DATA `input rows` = SELECT 1 AS key; DATA `graph value` = PROPERTY GRAPH (NODE TABLES (`input rows` AS `Person Set` KEY (key) LABEL `Human Label` NO PROPERTIES)); FROM `graph value` |> node_rows(definition: 'person set') |> SELECT key",
  )
  assert_true(
    semantic(program).contains("\"node_rows\":{\"definition\":\"person set\"}"),
  )
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
    NeedsInputs(_) => fail("Graph selection adds no acquisition")
  }
}
