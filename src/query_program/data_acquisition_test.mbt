///|
test "DATA imports the existing input once without adding a DATA capture" {
  let text = "DATA kept = FROM orders |> SELECT id; FROM kept |> SELECT id"
  let actual = compile_query_script(
    @query.parse_query_script(text, syntax_limits()).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  // This is authored from the existing input/step contract. DATA creates a
  // logical producer in main, not another acquisition or exported Result.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","select":["id"],"as":"aql_data_1"},{"from":"aql_data_1","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  assert_eq(@program.stage_count(actual), 1)
}
