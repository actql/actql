///|
fn temporal_join_source(call : String) -> String {
  "WITH l AS (SELECT 1 AS id, 10 AS at), r AS (SELECT 2 AS id, 5 AS begin, 15 AS finish), matched AS (FROM l AS left_rows |> " + call + ") SELECT id, value FROM matched ORDER BY id"
}

///|
fn temporal_join_control(operation : String, body : String) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.temporal_join_source\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"at\":10}]},\"as\":\"l\"},{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"begin\":{\"type\":\"number\",\"nullable\":false},\"finish\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2,\"begin\":5,\"finish\":15}]},\"as\":\"r\"},{\"from\":\"l\",\"" + operation + "\":" + body + ",\"as\":\"matched\"},{\"from\":\"matched\",\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"value\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"id\",\"value\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "adopted temporal calls reach existing two-input Owners without argument substitutions" {
  let cases = [
    ("asof_join", "asof_join(with: r, kind: 'left', by: [], left_id: left_rows.id, left_time: left_rows.at, right_time: r.begin, direction: 'backward', tolerance: 10, select: {id: left.id, value: right.id})", "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"at\",\"right_time\":\"begin\",\"direction\":\"backward\",\"tolerance\":10,\"select\":{\"id\":\"left.id\",\"value\":\"right.id\"}}"),
    ("interval_join", "interval_join(with: r, kind: 'left', mode: 'point_in_interval', on: [], left: {time: left_rows.at}, right: {start: r.begin, end: r.finish}, select: {id: left.id, value: right.id}, max_output_rows: 2)", "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"at\"},\"right\":{\"start\":\"begin\",\"end\":\"finish\"},\"select\":{\"id\":\"left.id\",\"value\":\"right.id\"},\"max_output_rows\":2}")
  ]
  for (operation, call, body) in cases {
    let control = temporal_join_control(operation, body)
    event_window_common_checked(control)
    let actual = @frontend.lower(temporal_join_source(call), Sql, Some({..pair_context(), inputs:[]})).unwrap().program.unwrap()
    event_window_common_checked(actual)
    let actual_body = with_carrier_argument(actual, operation)
    let physical = actual_body.split("\"with\":\"")[1].split("\"")[0]
    assert_eq(actual_body.replace(old=physical,new="r"), with_carrier_argument(control, operation))
  }
}
