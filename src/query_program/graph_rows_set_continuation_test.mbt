///|
fn graph_row_set_continuation_program(
  in_binding : Bool,
) -> @program.Program raise {
  let prefix = "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)))) "
  let body = "FROM g |> node_rows() |> SELECT p AS value |> UNION ALL (FROM n |> SELECT p + 1 AS other)"
  let source = if in_binding {
    prefix + ", combined AS (" + body + ") FROM combined |> ORDER BY value"
  } else {
    prefix + body + " |> ORDER BY value"
  }
  match
    compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(program) => program
    Err(_) => fail("the existing Graph-row set head must remain supported")
  }
}

///|
// One authored UNION has one relational append. An inner Graph-row
// continuation must not consume the outer set owner's right operand again.
test "Graph row root continuation leaves exactly one append to the set owner" {
  let program = graph_row_set_continuation_program(false)
  assert_eq(semantic(program).split("\"append\":").length() - 1, 1)
  assert_eq(semantic(program).split("\"sort\":").length() - 1, 1)
}

///|
test "Graph row WITH continuation leaves exactly one append to the set owner" {
  let program = graph_row_set_continuation_program(true)
  assert_eq(semantic(program).split("\"append\":").length() - 1, 1)
  assert_eq(semantic(program).split("\"sort\":").length() - 1, 1)
}

///|
test "Graph row Carrier continuation keeps the original set head ownership" {
  let source = "WITH n AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) PROPERTIES (occurred_ms)))) FROM g |> node_rows() |> to_events(id: node_key, time: occurred_ms) |> events() |> SELECT node_key, occurred_ms |> UNION ALL (FROM n |> SELECT node_key, occurred_ms) |> ORDER BY node_key"
  let program = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  let body = semantic(program)
  assert_eq(body.split("\"append\":").length() - 1, 1)
  assert_eq(body.split("\"sort\":").length() - 1, 1)
  for operation in ["node_rows", "to_events", "events"] {
    assert_eq(body.split("\"" + operation + "\":").length() - 1, 1)
  }
  match
    @check.check_parsed_with_evidence(
      program,
      graph_event_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("the original source-free set has no acquisition")
  }
}
