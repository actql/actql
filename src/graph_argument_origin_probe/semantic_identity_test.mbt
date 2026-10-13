///|
// Existing independently authored machine-Program fixture, not compiler output.
fn graph_diagnostic_expected(
  operation : String,
  body : String,
  fields : String,
) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.graph_argument_origin\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]},\"as\":\"aql_script_seed_1\"},{\"from\":\"aql_script_seed_1\",\"derive\":{\"aql_query_expr_0\":{\"literal\":1}}},{\"select\":[{\"node_key\":\"aql_query_expr_0\"}],\"as\":\"aql_script_cte_0\"},{\"graph\":{\"version\":\"actql-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"aql_script_cte_0\",\"key\":[\"node_key\"],\"labels\":[{\"name\":\"Node\",\"properties\":{\"mode\":\"no_properties\"}}]}],\"edges\":[]},\"as\":\"aql_with_graph_2\"},{\"from\":\"aql_with_graph_2\",\"" +
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
fn semantic(program : @program.Program) -> String raise {
  let writer = @encode.writer(100000, 10000, 100)
  @program.emit_metadata_stripped_program(program, writer)
  @encode.finish(writer)
}

///|
test "argument provenance leaves the independent complete Graph Program preimage unchanged" {
  let prefix = "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) "
  for
    (operation, args, body, selected, fields) in [
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
    let actual = @query.compile_query_script(
      @syntax.parse_query_script(
        prefix +
        "FROM g |> " +
        operation +
        "(" +
        args +
        ") |> SELECT " +
        selected,
        syntax_limits(),
      ).unwrap(),
      context(),
      construction_limits(),
    ).unwrap()
    assert_eq(
      semantic(actual),
      semantic(graph_diagnostic_expected(operation, body, fields)),
    )
  }
}
