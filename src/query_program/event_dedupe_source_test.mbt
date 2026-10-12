///|
// Complete machine controls are authored independently of frontend output.
// Event identity is distinct from business grouping and explicit order fields.
fn event_dedupe_control(by : String, order : String) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.event_dedupe\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    "{\"values\":{\"schema\":{\"event_id\":{\"type\":\"number\",\"nullable\":false},\"occurred_ms\":{\"type\":\"number\",\"nullable\":false},\"bucket\":{\"type\":\"number\",\"nullable\":true},\"score\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"event_id\":1,\"occurred_ms\":20,\"bucket\":null,\"score\":null},{\"event_id\":2,\"occurred_ms\":10,\"bucket\":null,\"score\":7},{\"event_id\":3,\"occurred_ms\":30,\"bucket\":2,\"score\":5},{\"event_id\":4,\"occurred_ms\":5,\"bucket\":2,\"score\":null}]},\"as\":\"rows\"}," +
    "{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_ms\"},\"as\":\"ev\"}," +
    "{\"from\":\"ev\",\"dedupe_events\":{\"by\":" +
    by +
    ",\"order_by\":" +
    order +
    "},\"as\":\"picked\"}," +
    "{\"from\":\"picked\",\"events\":true},{\"sort\":[{\"field\":\"event_id\",\"dir\":\"asc\",\"nulls\":\"first\"}]}," +
    "{\"select\":[\"event_id\",\"occurred_ms\",\"bucket\",\"score\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"event_id\",\"occurred_ms\",\"bucket\",\"score\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn event_dedupe_rows() -> String {
  "SELECT 1 AS event_id, 20 AS occurred_ms, CAST(NULL AS FLOAT64) AS bucket, CAST(NULL AS FLOAT64) AS score UNION ALL SELECT 2, 10, CAST(NULL AS FLOAT64), 7 UNION ALL SELECT 3, 30, 2, 5 UNION ALL SELECT 4, 5, 2, CAST(NULL AS FLOAT64)"
}

///|
fn event_dedupe_source(by : String, order : String) -> String {
  "WITH rows AS (" +
  event_dedupe_rows() +
  "), " +
  "ev AS (FROM rows |> to_events(id: event_id, time: occurred_ms)), " +
  "picked AS (FROM ev |> dedupe_events(by: " +
  by +
  ", order_by: " +
  order +
  ")), " +
  "result_rows AS (FROM picked |> events()) " +
  "SELECT event_id, occurred_ms, bucket, score FROM result_rows ORDER BY event_id"
}

///|
test "P2 independent event dedupe accepts global repeated nullable grouping and both OrderKeys" {
  for by in ["[]", "[\"bucket\"]", "[\"bucket\",\"bucket\"]"] {
    for
      order in [
        "[{\"occurred_ms\":\"asc\"}]", "[{\"field\":\"score\",\"dir\":\"desc\",\"nulls\":\"last\"},{\"event_id\":\"asc\"}]",
      ] {
      event_window_common_checked(event_dedupe_control(by, order))
    }
  }
}

///|
test "P2 dedupe source retains every partition occurrence and explicit OrderKey" {
  for
    (by, expected_by) in [
      ("[]", "[]"),
      ("[bucket]", "[\"bucket\"]"),
      ("[bucket, BUCKET]", "[\"bucket\",\"bucket\"]"),
    ] {
    let actual = with_carrier_program(
      event_dedupe_source(
        by, "[{field: SCORE, dir: 'desc', nulls: 'last'}, {field: event_id, dir: 'asc', nulls: 'first'}]",
      ),
      { ..pair_context(), inputs: [], },
    ).unwrap()
    let expected = event_dedupe_control(
      expected_by, "[{\"field\":\"score\",\"dir\":\"desc\",\"nulls\":\"last\"},{\"field\":\"event_id\",\"dir\":\"asc\",\"nulls\":\"first\"}]",
    )
    assert_eq(
      with_carrier_argument(actual, "dedupe_events"),
      with_carrier_argument(expected, "dedupe_events"),
    )
    event_window_common_checked(actual)
  }
}

///|
test "P2 shorthand dedupe order keeps typed field names and omitted null placement" {
  let actual = with_carrier_program(
    event_dedupe_source(
      "[bucket]", "[{OCCURRED_MS: 'asc'}, {`event_id`: 'desc'}]",
    ),
    { ..pair_context(), inputs: [], },
  ).unwrap()
  let expected = event_dedupe_control(
    "[\"bucket\"]", "[{\"occurred_ms\":\"asc\"},{\"event_id\":\"desc\"}]",
  )
  assert_eq(
    with_carrier_argument(actual, "dedupe_events"),
    with_carrier_argument(expected, "dedupe_events"),
  )
  event_window_common_checked(actual)
}

///|
test "P2 dedupe common refusals keep wrong Carrier and exact OrderKey causes" {
  let prefix = "WITH rows AS (" + event_dedupe_rows() + "), ev AS (FROM rows |> to_events(id: event_id, time: occurred_ms)) "
  let cases : Array[(String, @pipeline.IssueKind)] = [
    ("FROM rows |> dedupe_events(by: [], order_by: [{event_id: 'asc'}])", Event(WrongCarrier(RelationKind))),
    ("FROM ev |> dedupe_events(by: [], order_by: [])", Event(InvalidOrder)),
    ("FROM ev |> dedupe_events(by: [], order_by: [{score: 'ASC'}])", Event(InvalidOrder)),
    ("FROM ev |> dedupe_events(by: [], order_by: [{field: score, dir: 'asc', nulls: 'LAST'}])", Event(InvalidOrder)),
    ("FROM ev |> dedupe_events(by: [], order_by: [{field: score, dir: 'asc'}])", Event(Decode(MissingField))),
  ]
  for (call, expected) in cases {
    assert_eq(event_window_issue(prefix + call), expected)
  }
  for order in ["[{missing: 'asc'}]", "[{`SCORE`: 'asc'}]", "[{field: missing, dir: 'asc', nulls: 'last'}]"] {
    assert_true(with_carrier_program(event_dedupe_source("[]", order), {..pair_context(), inputs: [],}) is Err(UnknownColumn), msg=order)
  }
  assert_true(with_carrier_program(prefix + "FROM ev |> dedupe_events(by: [], order_by: [{score: 'asc'}], max_output_rows: 1)", {..pair_context(), inputs: [],}) is Err(InvalidQuery))
}

///|
test "P2 dedupe cannot resurrect a dropped grouping field or range alias" {
  let rows = "WITH rows AS (" + event_dedupe_rows() + ") "
  for call in [
    "dedupe_events(by: [bucket], order_by: [{event_id: 'asc'}])",
    "dedupe_events(by: [], order_by: [{old.event_id: 'asc'}])",
  ] {
    assert_true(with_carrier_program(rows + "FROM rows |> AS old |> SELECT event_id, occurred_ms |> to_events(id: event_id, time: occurred_ms) |> " + call,
      {..pair_context(), inputs: [],}) is Err(UnknownColumn), msg=call)
  }
}
