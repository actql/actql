///|
// Events remain Events through aliases. An explicit Graph requirement must be
// checked before unused-demand pruning or a Carrier-only early return.
test "explicit Graph expectation rejects an Events alias before demand" {
  let prefix = "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), e AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)), "
  for
    tail in [
      "not_a_graph AS (FROM GRAPH e) FROM not_a_graph |> events() |> SELECT event_id",
      "unused AS (FROM GRAPH e) SELECT 1 AS answer",
    ] {
    let parsed = @query.parse_query_script(prefix + tail, syntax_limits())
    .unwrap()
    let actual = compile_query_script(
      parsed,
      { ..pair_context(), inputs: [], },
      construction_limits(),
    )
    assert_true(actual is Err(InvalidQuery), msg=tail)
  }
}
