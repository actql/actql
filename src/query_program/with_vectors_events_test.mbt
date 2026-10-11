///|
fn with_carrier_program(text : String, context : Context) -> Result[@program.Program, Issue] {
  compile_query_script(
    @query.parse_query_script(text, syntax_limits()).unwrap(),
    context, construction_limits(),
  )
}

///|
test "WITH preserves Vectors between bindings and only vectors bridges to Relation" {
  let text = "WITH prepared AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)), scored AS (FROM prepared |> score_vectors(query: [1, 0], metric: 'dot')), ranked_rows AS (FROM scored |> vectors()) SELECT item_id, score FROM ranked_rows ORDER BY score DESC, item_id"
  let actual = with_carrier_program(text, nearest_context()).unwrap()
  let body = semantic(actual)
  assert_true(body.contains("\"to_vectors\":{\"id\":\"item_id\",\"vector\":\"embedding\"}"))
  assert_true(body.contains("\"score_vectors\":{\"query\":[1,0],\"metric\":\"dot\"}"))
  assert_true(body.contains("\"vectors\":true"))
  match @check.check_parsed(actual, check_environment(veca=true), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed vector input")
  }
}

///|
test "WITH Events session keeps typed clock and explicit bridge" {
  let actual = with_carrier_program(
    "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms, 'u' AS customer_id UNION ALL SELECT 2, 299999, 'u' UNION ALL SELECT 3, 599999, 'u'), ev AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)), grouped AS (FROM ev |> session(by: [customer_id], gap: '5m')), event_result AS (FROM grouped |> events()) SELECT event_id, session_start_ms, session_end_ms FROM event_result ORDER BY event_id",
    { ..pair_context(), inputs: [], },
  ).unwrap()
  let body = semantic(actual)
  assert_true(body.contains("\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_ms\"}"))
  assert_true(body.contains("\"session\":{\"by\":[\"customer_id\"],\"gap\":\"5m\"}"))
  assert_true(body.contains("\"events\":true"))
}

///|
test "WITH typed producer cannot use a row range or skip explicit bridge" {
  let prefix = "WITH prepared AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) "
  for tail in ["FROM prepared AS p |> vectors()", "FROM prepared |> AS p |> vectors()"] {
    assert_true(with_carrier_program(prefix + tail, nearest_context()) is Err(RangeAliasRequiresRelation))
  }
  assert_true(with_carrier_program(prefix + "SELECT item_id FROM prepared", nearest_context()) is Err(UnsupportedProjection))
  assert_true(with_carrier_program(prefix + "FROM prepared |> vectors() |> AS p |> SELECT p.item_id", nearest_context()) is Ok(_))
}
