///|
// Events remain Events through aliases. An explicit Graph requirement must be
// checked before unused-demand pruning or a Carrier-only early return.
fn assert_explicit_graph_expectation(tail : String) -> Unit raise {
  let prefix = "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), e AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)), "
  assert_graph_expected_source(prefix + tail, { ..pair_context(), inputs: [], })
}

///|
fn assert_graph_expected_source(text : String, context : Context) -> Unit raise {
  let parsed = @query.parse_query_script(text, syntax_limits()).unwrap()
  match compile_query_script(parsed, context, construction_limits()) {
    Ok(program) =>
      fail(
        "Graph expectation was accepted; actual Program: " + semantic(program),
      )
    Err(issue) => {
      guard issue is GraphExpected(Some(origin)) else {
        fail("Expected the authored Graph operand refusal: " + text)
      }
      assert_eq(@origin.kind(origin), @origin.Authored)
      assert_true(@origin.belongs_to(@query.script_document(parsed), origin))
      assert_true(
        @origin.span(origin).end_byte > @origin.span(origin).start_byte,
      )
    }
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
  assert_explicit_graph_expectation(
    "unused AS (FROM GRAPH e) SELECT 1 AS answer",
  )
}

///|
test "explicit Graph expectation applies at the root Carrier dispatch" {
  assert_graph_expected_source(
    "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), e AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)) FROM GRAPH e |> events() |> SELECT event_id",
    { ..pair_context(), inputs: [], },
  )
}

///|
test "explicit Graph expectation rejects a Relation before alias return" {
  assert_graph_expected_source(
    "WITH source_rows AS (SELECT 1 AS event_id), unused AS (FROM GRAPH source_rows) SELECT 1 AS answer",
    { ..pair_context(), inputs: [], },
  )
}

///|
test "explicit Graph expectation rejects Vectors through the common Carrier" {
  assert_graph_expected_source(
    "WITH v AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)), unused AS (FROM GRAPH v) SELECT 1 AS answer",
    nearest_context(),
  )
}

///|
test "a nearer Events binding cannot fall back to an outer Graph" {
  assert_graph_expected_source(
    "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (event_id) PROPERTIES (event_id, occurred_ms)))) FROM (WITH g AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)), chosen AS (FROM GRAPH g) FROM chosen |> events() |> SELECT event_id)",
    { ..pair_context(), inputs: [], },
  )
}

///|
test "Graph expectation and ordinary Graph binding retain the same producer" {
  let prefix = with_graph_alias_prefix()
  let marked = compile_with_set(
    prefix + ", chosen AS (FROM GRAPH g) FROM chosen |> node_rows() |> SELECT p",
  )
  let unmarked = compile_with_set(
    prefix + ", chosen AS (FROM g) FROM chosen |> node_rows() |> SELECT p",
  )
  assert_eq(semantic(marked), semantic(unmarked))
  assert_eq(semantic(marked).split("\"graph\":{").length(), 2)
}
