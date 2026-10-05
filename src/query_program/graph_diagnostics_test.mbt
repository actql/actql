///|
fn graph_diagnostic_prefix() -> String {
  "DATA n = SELECT 1 AS node_key; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES)); "
}

///|
// Complete expected Programs are authored from the existing machine contract.
// Neither the query compiler nor the Graph diagnostic owner supplies them.
fn graph_diagnostic_expected(
  operation : String,
  body : String,
  fields : String,
) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]},\"as\":\"aql_script_seed_1\"},{\"from\":\"aql_script_seed_1\",\"derive\":{\"aql_query_expr_0\":{\"literal\":1}}},{\"select\":[{\"node_key\":\"aql_query_expr_0\"}],\"as\":\"aql_data_0\"},{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"aql_data_0\",\"key\":[\"node_key\"],\"labels\":[{\"name\":\"Node\",\"properties\":{\"mode\":\"no_properties\"}}]}],\"edges\":[]},\"as\":\"aql_data_2\"},{\"from\":\"aql_data_2\",\"" +
    operation +
    "\":" +
    body +
    ",\"as\":\"aql_sga_3\"},{\"from\":\"aql_sga_3\",\"select\":" +
    fields +
    ",\"as\":\"aql_script_result\"}],\"results\":{\"rows\":{\"from\":\"aql_script_result\",\"fields\":" +
    fields +
    "}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Graph diagnostics independent machine Programs pass the common checker" {
  for
    (operation, body, fields) in [
      ("degree", "{\"direction\":\"both\"}", "[\"degree\",\"node\"]"),
      (
        "graph_bounds", "{\"max_nodes\":0,\"max_edges\":0,\"max_degree\":0}", "[\"actual\",\"kind\",\"node_id\",\"max\"]",
      ),
      (
        "components", "{\"kind\":\"strong\",\"max_output_rows\":1}", "[\"component_size\",\"node_id\",\"component_id\"]",
      ),
    ] {
    match
      @check.check_parsed_with_evidence(
        graph_diagnostic_expected(operation, body, fields),
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) => fail("Diagnostic operation adds no acquisition")
    }
  }
}

///|
test "Graph diagnostics text matches independent complete machine Programs" {
  for
    (operation, arguments, body, selected, fields) in [
      (
        "degree", "direction: 'both'", "{\"direction\":\"both\"}", "degree, node",
        "[\"degree\",\"node\"]",
      ),
      (
        "graph_bounds", "max_nodes: 0, max_edges: 0, max_degree: 0", "{\"max_nodes\":0,\"max_edges\":0,\"max_degree\":0}",
        "actual, kind, node_id, max", "[\"actual\",\"kind\",\"node_id\",\"max\"]",
      ),
      (
        "components", "kind: 'strong', max_output_rows: 1", "{\"kind\":\"strong\",\"max_output_rows\":1}",
        "component_size, node_id, component_id", "[\"component_size\",\"node_id\",\"component_id\"]",
      ),
    ] {
    let actual = compile_data_set(
      graph_diagnostic_prefix() +
      "FROM g |> " +
      operation +
      "(" +
      arguments +
      ") |> SELECT " +
      selected,
    )
    assert_eq(
      semantic(actual),
      semantic(graph_diagnostic_expected(operation, body, fields)),
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
      NeedsInputs(_) => fail("Diagnostic source adds no acquisition")
    }
  }
}

///|
test "Graph diagnostic DATA reuses the normalized producer and current columns" {
  let program = compile_data_set(
    graph_diagnostic_prefix() +
    "DATA `stats` = FROM g |> normalize_graph() |> degree(direction: 'out'); FROM `stats` |> WHERE degree = 0 |> SELECT degree, node |> ORDER BY degree |> LIMIT 1",
  )
  let body = semantic(program)
  assert_eq(body.split("\"property_graph\":").length(), 2)
  assert_eq(body.split("\"degree\":{").length(), 2)
  assert_true(body.contains("\"normalize_graph\":true"))
  assert_true(body.contains("\"take\":{\"count\":1,\"offset\":0}"))
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
    NeedsInputs(_) => fail("Diagnostic DATA adds no acquisition")
  }
}

///|
test "Graph diagnostic invalid bodies reach the existing common checker" {
  for
    operation in [
      "degree() |> SELECT degree", "degree(direction: 'invented') |> SELECT degree",
      "degree(direction: 'both', extra: true) |> SELECT degree", "graph_bounds() |> SELECT kind",
      "graph_bounds(max_nodes: -1) |> SELECT kind", "graph_bounds(max_edges: 1.5) |> SELECT kind",
      "components(kind: 'invented') |> SELECT component_size", "components(kind: 'weak', max_output_rows: 0) |> SELECT component_size",
    ] {
    let program = compile_data_set(
      graph_diagnostic_prefix() + "FROM g |> " + operation,
    )
    assert_true(
      @check.check_parsed_with_evidence(
        program,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      )
      is Rejected(_),
      msg=operation,
    )
  }
}

///|
test "Graph diagnostic transition rejects Graph columns and another Graph call" {
  for
    (suffix, graph_call) in [
      ("degree(direction: 'in') |> SELECT node_key", false),
      ("graph_bounds(max_nodes: 0) |> SELECT node", false),
      ("components(kind: 'weak') |> SELECT degree", false),
      ("degree(direction: 'both') |> node_rows() |> SELECT id", true),
    ] {
    let source = graph_diagnostic_prefix() + "FROM g |> " + suffix
    let actual = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    assert_true(
      if graph_call {
        actual is Err(UnsupportedGraph)
      } else {
        actual is Err(UnknownColumn)
      },
      msg=suffix,
    )
  }
}

///|
test "Graph diagnostic typed parameters retain declarations and binding rules" {
  let script = @query.parse_query_script(
    graph_diagnostic_prefix() +
    "FROM g |> graph_bounds(max_nodes: @p) |> SELECT actual, kind, node_id, max",
    syntax_limits(),
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(number_parameter_declarations()),
  }
  let actual = compile_query_script(script, context, construction_limits()).unwrap()
  let expected_body = semantic(
    graph_diagnostic_expected(
      "graph_bounds", "{\"max_nodes\":{\"$param\":\"p\"}}", "[\"actual\",\"kind\",\"node_id\",\"max\"]",
    ),
  ).replace(
    old="\"stages\":",
    new="\"params\":{\"p\":{\"type\":\"number\"}},\"stages\":",
  )
  let expected = @program.parse(
    expected_body,
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  assert_true(
    @check.check_parsed_with_evidence(
      actual,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    )
    is NeedsInputs(_),
  )
  for
    (value, accepted) in [
      ("{\"p\":0}", true),
      ("{\"p\":-1}", false),
      ("{\"p\":\"zero\"}", false),
    ] {
    let values = @wire.admit(
      @source.parse_json(value, construction_limits().source.source).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
    let result = @check.check_parsed_with_evidence(
      actual,
      graph_rows_environment(),
      Some(values),
      [],
      graph_rows_check_limits(),
    )
    assert_true(
      if accepted {
        result is Checked(_)
      } else {
        result is Rejected(_)
      },
      msg=value,
    )
  }
}
