///|
fn graph_diagnostic_prefix() -> String {
  "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) "
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
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]},\"as\":\"aql_script_seed_1\"},{\"from\":\"aql_script_seed_1\",\"derive\":{\"aql_query_expr_0\":{\"literal\":1}}},{\"select\":[{\"node_key\":\"aql_query_expr_0\"}],\"as\":\"aql_script_cte_0\"},{\"graph\":{\"version\":\"actql-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"aql_script_cte_0\",\"key\":[\"node_key\"],\"labels\":[{\"name\":\"Node\",\"properties\":{\"mode\":\"no_properties\"}}]}],\"edges\":[]},\"as\":\"aql_with_graph_2\"},{\"from\":\"aql_with_graph_2\",\"" +
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
test "Graph diagnostic WITH reuses the normalized producer and current columns" {
  let program = compile_data_set(
    graph_diagnostic_prefix() +
    " , `stats` AS (FROM g |> normalize_graph() |> degree(direction: 'out')) FROM `stats` |> WHERE degree = 0 |> SELECT degree, node |> ORDER BY degree |> LIMIT 1",
  )
  let body = semantic(program)
  assert_eq(body.split("\"graph\":").length(), 2)
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
    NeedsInputs(_) => fail("Diagnostic WITH adds no acquisition")
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
    expect_with_graph_static_refusal(
      graph_diagnostic_prefix() + "FROM g |> " + operation,
    )
  }
}

///|
test "Graph diagnostic transition rejects Graph columns and another Graph call" {
  for
    (suffix, field_range) in [
      ("degree(direction: 'in') |> SELECT node_key", Some((154, 162))),
      ("graph_bounds(max_nodes: 0) |> SELECT node", Some((157, 161))),
      ("components(kind: 'weak') |> SELECT degree", Some((155, 161))),
      ("degree(direction: 'both') |> node_rows() |> SELECT id", None),
    ] {
    let source = graph_diagnostic_prefix() + "FROM g |> " + suffix
    let actual = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    if field_range is Some((start, end)) {
      guard actual
        is Err(
          Expression(
            { issue: @expression.UnknownReference, origin: Some(origin), }
          )
        ) else {
        fail("diagnostic output must reject the unavailable field: " + suffix)
      }
      assert_eq(@origin.kind(origin), @origin.Authored)
      let span = @origin.span(origin)
      assert_eq(span.start_byte, start)
      assert_eq(span.end_byte, end)
    } else {
      assert_true(actual is Err(InvalidQuery), msg=suffix)
    }
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

///|
test "Graph components WITH admits both kinds and retains its current Relation schema" {
  for kind in ["weak", "strong"] {
    let actual = compile_data_set(
      graph_diagnostic_prefix() +
      ", selected AS (FROM g |> components(kind: '" +
      kind +
      "')) FROM selected |> SELECT node_id, component_id, component_size",
    )
    // WITH reserves a name before its Graph-to-Relation operation. The alias
    // retains that producer; it does not synthesize a Graph copy or extra step.
    let expected = @program.parse(
      semantic(
        graph_diagnostic_expected(
          "components",
          "{\"kind\":\"" + kind + "\"}",
          "[\"node_id\",\"component_id\",\"component_size\"]",
        ),
      )
      .split("aql_sga_3")
      .join("aql_sga_4"),
      construction_limits().program,
      format=Json,
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
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
        NeedsInputs(_) => fail("components WITH adds no acquisition")
      }
    }
  }
}

///|
test "Graph components invalid arguments retain exact common-checker reasons and locations" {
  let cases : Array[(String, @pipeline.IssueKind, String)] = [
    ("kind: 'invented'", Graph(InvalidBody), "kind"),
    ("kind: 'weak', max_output_rows: 0", Graph(InvalidCount), "max_output_rows"),
  ]
  for (arguments, expected, field) in cases {
    let actual = classified_graph_source(
      graph_diagnostic_prefix() +
      "FROM g |> components(" +
      arguments +
      ") |> SELECT component_size",
    )
    guard actual
      is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
      fail("components must retain its common static body refusal")
    }
    assert_eq(stage, 0)
    assert_eq(issue.kind, expected)
    assert_eq(issue.path, [
      Key("stages"),
      Index(0),
      Key("steps"),
      Index(4),
      Key("components"),
      Key(field),
    ])
    // The common issue retains the authored call span before E's diagnostic
    // projection decides whether any public position can be disclosed.
    let prefix = graph_diagnostic_prefix() + "FROM g |> "
    assert_eq(issue.span.start_byte, @utf8.encode(prefix).length())
    assert_eq(
      issue.span.end_byte,
      @utf8.encode(prefix + "components(" + arguments + ")").length(),
    )
  }
}
