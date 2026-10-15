// Original interval-left inputs; observations are diagnostic, never an oracle.

///|
test "public temporal interval lowering preserves original arguments and input topology" {
  let control = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.temporal_interval-left\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"at\":10},{\"id\":2,\"at\":30},{\"id\":3,\"at\":50}]},\"as\":\"l\"},{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"begin\":{\"type\":\"number\",\"nullable\":false},\"finish\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":7,\"begin\":5,\"finish\":15},{\"id\":8,\"begin\":20,\"finish\":25}]},\"as\":\"r\"},{\"from\":\"l\",\"interval_join\":{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"at\"},\"right\":{\"start\":\"begin\",\"end\":\"finish\"},\"select\":{\"id\":\"left.id\",\"value\":\"right.id\"},\"max_output_rows\":3},\"as\":\"matched\"},{\"from\":\"matched\",\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"value\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"id\",\"value\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = @frontend.lower(
    "WITH l AS (SELECT 1 AS id, 10 AS `at` UNION ALL SELECT 2, 30 UNION ALL SELECT 3, 50), r AS (SELECT 7 AS id, 5 AS begin, 15 AS finish UNION ALL SELECT 8, 20, 25), matched AS (FROM l AS `current` |> interval_join(with: r, kind: 'left', mode: 'point_in_interval', on: [], left: {time: current.at}, right: {start: r.begin, end: r.finish}, select: {id: left.id, value: right.id}, max_output_rows: 3)) SELECT id, value FROM matched ORDER BY id",
    Sql,
    Some({ ..pair_context(), inputs: [], }),
  ).unwrap().program.unwrap()
  event_window_common_checked(control)
  let body = with_carrier_argument(actual, "interval_join")
  let physical = body.split("\"with\":\"").collect()[1].split("\"").collect()[0].to_owned()
  assert_eq(
    body.replace(old=physical, new="r"),
    with_carrier_argument(control, "interval_join"),
  )
  let writer = @encode.writer(100000, 10000, 100)
  @program.emit_program_source(actual, writer)
  println("ACTQL_TEMPORAL_LOWERED " + @encode.finish(writer))
}
