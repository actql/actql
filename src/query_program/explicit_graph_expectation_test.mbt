///|
// Events remain Events through aliases. An explicit Graph requirement must be
// checked before unused-demand pruning or a Carrier-only early return.
fn assert_explicit_graph_expectation(tail : String) -> Unit raise {
  let prefix = "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), e AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)), "
  let parsed = @query.parse_query_script(prefix + tail, syntax_limits()).unwrap()
  match compile_query_script(
    parsed,
    { ..pair_context(), inputs: [], },
    construction_limits(),
  ) {
    Ok(program) =>
      fail("Graph expectation was accepted; actual Program: " + semantic(program))
    Err(issue) => assert_true(issue is InvalidQuery, msg=tail)
  }
}

///|
test "explicit Graph expectation rejects a demanded Events alias" {
  assert_explicit_graph_expectation(
    "not_a_graph AS (FROM GRAPH e) FROM not_a_graph |> events() |> SELECT event_id",
  )
}

///|
test "explicit Graph expectation rejects an unused Events alias" {
  assert_explicit_graph_expectation("unused AS (FROM GRAPH e) SELECT 1 AS answer")
}
