///|
test "Graph definition selector has an independent complete Program" {
  let actual = compile_with_set(
    "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p)))) FROM g |> node_rows(definition: 'n') |> SELECT p, node_key",
  )
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","node_rows":{"definition":"n"},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["p","node_key"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["p","node_key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "Graph selectors preserve declared fields and common checking" {
  let prefix = "WITH n AS (SELECT 1 AS node_key, CAST(NULL AS FLOAT64) AS p), m AS (SELECT 2 AS other_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p), m AS M KEY (other_key) LABEL Company NO PROPERTIES))) "
  for
    suffix in [
      "FROM g |> node_rows(definition: 'n') |> SELECT node_key, p, labels", "FROM g |> node_rows(label: 'PERSON') |> SELECT node_key, p, labels",
      ", `rows` AS (FROM g |> node_rows(label: 'Company') |> SELECT other_key) FROM rows |> ORDER BY other_key",
    ] {
    let program = compile_with_set(prefix + suffix)
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
  let prefix = "WITH n AS (SELECT 1 AS key, 7 AS p, 8 AS q), m AS (SELECT 2 AS key, 9 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (key) LABEL Person PROPERTIES (p) LABEL Owner PROPERTIES (q), m AS M KEY (key) LABEL Person PROPERTIES (p)))) "
  // The selected label chooses definitions, not just its own properties.
  // q exists on N but remains Conditional across N and M.
  for
    suffix in [
      "FROM g |> node_rows(label: 'Person') |> SELECT q", "FROM g |> node_rows(label: 'Person') |> WHERE q IS NOT NULL |> SELECT key",
    ] {
    // The same common presence obligation now rejects during WITH static
    // admission, before returning a complete Program for a second check.
    expect_with_graph_static_refusal(
      prefix + suffix,
      expected=Some(@pipeline.Operation(@relation.PresenceRequired("q"))),
    )
  }
  let program = compile_with_set(
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
  let program = compile_with_set(
    "WITH `input rows` AS (SELECT 1 AS key), `graph value` AS (GRAPH (NODE TABLES (`input rows` AS `Person Set` KEY (key) LABEL `Human Label` NO PROPERTIES))) FROM `graph value` |> node_rows(definition: 'person set') |> SELECT key",
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

///|
test "Graph edge selectors retain the existing typed Bridge" {
  for selector in ["definition: 'e'", "label: 'r'"] {
    let program = compile_with_set(
      graph_rows_prefix() +
      "FROM g |> edge_rows(" +
      selector +
      ") |> SELECT edge_key, labels |> ORDER BY edge_key",
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
      NeedsInputs(_) => fail("Graph edge selection adds no acquisition")
    }
  }
}
