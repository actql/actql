///|
fn graph_relation_join_cases() -> Array[(String, String, String, String)] {
  [
    ("degree", "{\"direction\":\"out\"}", "direction: 'out'", "degree"),
    (
      "components", "{\"kind\":\"weak\",\"max_output_rows\":10}", "kind: 'weak', max_output_rows: 10",
      "component_size",
    ),
    ("graph_bounds", "{\"max_nodes\":0}", "max_nodes: 0", "actual"),
    ("graphs_equal", "{\"with\":\"g\"}", "with: g", "equal"),
    ("graph_diff", "{\"with\":\"g\"}", "with: g", "delta"),
    (
      "match_nodes", "{\"definition\":\"N\",\"where\":{\"literal\":true},\"fields\":[\"p\"]}",
      "definition: 'N', where: {literal: true}, fields: ['p']", "p",
    ),
    (
      "match_edges", "{\"definition\":\"E\",\"fields\":[\"p\"]}", "definition: 'E', fields: ['p']",
      "p",
    ),
  ]
}

///|
test "Ordered Graph Relation JOIN retains established singleton equality order" {
  let prefix = "WITH n AS (SELECT 1 AS node_key, 7 AS p), r AS (SELECT 10 AS tag), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)) EDGE TABLES (n AS E KEY (node_key) SOURCE KEY (node_key) REFERENCES N DESTINATION KEY (node_key) REFERENCES N LABEL R PROPERTIES (p)))) "
  for
    (operation, arguments, source_arguments, field) in graph_relation_join_cases() {
    let source = prefix +
      "FROM g |> " +
      operation +
      "(" +
      source_arguments +
      ") |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT l." +
      field +
      " AS value, rr.tag AS tag |> ORDER BY tag"
    for
      program in [
        graph_relation_join_control(operation, arguments, field, ordered=true),
        compile_with_set(source),
      ] {
      let checked = @check.check_parsed_with_evidence(
        program,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      )
      match checked {
        Checked(_) => ()
        Rejected(diagnostic) => graph_rows_rejected(diagnostic)
        NeedsInputs(_) => fail("ordered control needs no external Source")
      }
    }
  }
}

///|
// Independent complete common operations, not source-compiler output.
fn graph_relation_join_control(
  operation : String,
  arguments : String,
  field : String,
  ordered? : Bool = false,
) -> @program.Program {
  let source =
    #|{"version":"actql/0.1","id":"fixture.graph_relation_join","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":false}},"rows":[{"node_key":1,"p":7}]},"as":"n"},{"values":{"schema":{"tag":{"type":"number","nullable":false}},"rows":[{"tag":10}]},"as":"r"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[{"name":"E","from":"n","key":["node_key"],"source":{"definition":"N","key":["node_key"]},"target":{"definition":"N","key":["node_key"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}]},"as":"g"},{"from":"g","__operation__":__arguments__,"as":"stats"},{"from":"stats","cross_join":{"with":"r","max_output_rows":10,"select":{"value":"left.__field__","tag":"right.tag"}},"as":"joined"}__sort__],"results":{"rows":{"from":"__result__","fields":["value","tag"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  @program.parse(
    source
    .replace(old="__operation__", new=operation)
    .replace(old="__arguments__", new=arguments)
    .replace(old="__field__", new=field)
    .replace(
      old="__sort__",
      new=if ordered {
        ",{\"from\":\"joined\",\"sort\":[{\"field\":\"tag\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"sorted\"}"
      } else {
        ""
      },
    )
    .replace(old="__result__", new=if ordered { "sorted" } else { "joined" }),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Graph Relation JOIN controls pass the existing common checker" {
  for (operation, arguments, _, field) in graph_relation_join_cases() {
    match
      @check.check_parsed_with_evidence(
        graph_relation_join_control(operation, arguments, field),
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) => fail("common Graph Relation JOIN needs no Source")
    }
  }
}

///|
test "Existing Graph Relation calls remain Relation JOIN inputs" {
  let prefix = "WITH n AS (SELECT 1 AS node_key, 7 AS p), r AS (SELECT 10 AS tag), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)) EDGE TABLES (n AS E KEY (node_key) SOURCE KEY (node_key) REFERENCES N DESTINATION KEY (node_key) REFERENCES N LABEL R PROPERTIES (p)))) "
  for (operation, _, source_arguments, field) in graph_relation_join_cases() {
    let source = prefix +
      "FROM g |> " +
      operation +
      "(" +
      source_arguments +
      ") |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> SELECT l." +
      field +
      " AS value, rr.tag AS tag"
    let actual = compile_with_set(source)
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
      NeedsInputs(_) => fail("source Graph Relation JOIN needs no Source")
    }
    assert_true(semantic(actual).contains("\"max_output_rows\":10"))
    assert_true(semantic(actual).contains("\"fields\":[\"value\",\"tag\"]"))
  }
}
