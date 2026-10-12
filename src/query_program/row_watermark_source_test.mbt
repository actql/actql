///|
// Independent machine controls retain authored threshold sources and policy.
fn row_watermark_control(body : String, parameters? : Bool = false) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.row_watermark\"," +
    (if parameters { "\"params\":{\"p\":{\"type\":\"number\"}}," } else { "" }) +
    "\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"at\":10},{\"id\":2,\"at\":3}]},\"as\":\"rows\"}," +
    "{\"from\":\"rows\",\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"ordered\"}," +
    "{\"from\":\"ordered\",\"watermark_rows\":" + body + ",\"as\":\"marked\"}," +
    "{\"from\":\"marked\",\"select\":[\"id\",\"at\",\"watermark_ms\",\"watermark_late\",\"watermark_decision\"],\"as\":\"out\"}]," +
    "\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"id\",\"at\",\"watermark_ms\",\"watermark_late\",\"watermark_decision\"]}}}]," +
    "\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn row_watermark_source(call : String) -> String {
  "WITH rows AS (SELECT 1 AS id, 10 AS at UNION ALL SELECT 2, 3), " +
  "ordered AS (FROM rows |> ORDER BY id), " +
  "marked AS (FROM ordered AS r |> " + call + ") " +
  "SELECT id, at, watermark_ms, watermark_late, watermark_decision FROM marked"
}

///|
test "P2 independent row watermark preserves fixed and prefix threshold contracts" {
  for threshold in ["\"watermark_ms\":-0.5", "\"max_skew\":1", "\"max_skew\":\"1s\""] {
    for policy in ["mark", "drop"] {
      event_window_common_checked(row_watermark_control(
        "{\"time\":\"at\",\"late_policy\":\"" + policy + "\"," + threshold + "}",
      ))
    }
  }
  for name in ["watermark_ms", "max_skew"] {
    event_window_common_checked(row_watermark_control(
      "{\"time\":\"at\",\"late_policy\":\"mark\",\"" + name + "\":{\"$param\":\"p\"}}",
      parameters=true,
    ))
  }
}

///|
test "P2 row watermark source retains threshold policy and scoped time field" {
  for (threshold, expected) in [
    ("watermark_ms: -0.5", "\"watermark_ms\":-0.5"),
    ("max_skew: 1", "\"max_skew\":1"),
    ("max_skew: '1s'", "\"max_skew\":\"1s\""),
  ] {
    for policy in ["mark", "drop"] {
      let actual = with_carrier_program(
        row_watermark_source("watermark_rows(time: r.AT, late_policy: '" + policy + "', " + threshold + ")"),
        { ..pair_context(), inputs: [], },
      ).unwrap()
      let expected = row_watermark_control(
        "{\"time\":\"at\",\"late_policy\":\"" + policy + "\"," + expected + "}",
      )
      assert_eq(with_carrier_argument(actual, "watermark_rows"), with_carrier_argument(expected, "watermark_rows"))
      event_window_common_checked(actual)
    }
  }
}

///|
test "P2 row watermark whole Parameters keep declarations and threshold references" {
  for name in ["watermark_ms", "max_skew"] {
    let actual = with_carrier_program(
      row_watermark_source("watermark_rows(time: at, late_policy: 'mark', " + name + ": @p)"),
      { ..pair_context(), inputs: [], parameter_declarations: Some(number_parameter_declarations()), },
    ).unwrap()
    let expected = row_watermark_control(
      "{\"time\":\"at\",\"late_policy\":\"mark\",\"" + name + "\":{\"$param\":\"p\"}}",
      parameters=true,
    )
    assert_eq(with_carrier_argument(actual, "watermark_rows"), with_carrier_argument(expected, "watermark_rows"))
    event_window_common_checked(actual)
  }
}

///|
test "P2 row watermark retains common threshold and policy refusal reasons" {
  for call in [
    "watermark_rows(time: at, late_policy: 'mark')",
    "watermark_rows(time: at, late_policy: 'mark', watermark_ms: 0, max_skew: 1)",
    "watermark_rows(time: at, late_policy: 'MARK', watermark_ms: 0)",
  ] {
    assert_eq(event_window_issue(row_watermark_source(call)), Operation(InvalidBody))
  }
  for threshold in ["max_skew: 0", "max_skew: -1", "max_skew: 1.5"] {
    assert_eq(
      event_window_issue(row_watermark_source("watermark_rows(time: at, late_policy: 'mark', " + threshold + ")")),
      Operation(InvalidCount),
    )
  }
}

///|
test "P2 row watermark cannot resurrect dropped time or old aliases" {
  for time in ["at", "old.at"] {
    assert_true(with_carrier_program(
      "WITH rows AS (SELECT 1 AS id, 10 AS at) FROM rows |> AS old |> SELECT id |> watermark_rows(time: " + time + ", late_policy: 'mark', watermark_ms: 0)",
      { ..pair_context(), inputs: [], },
    ) is Err(UnknownColumn))
  }
  assert_true(with_carrier_program(
    row_watermark_source("watermark_rows(time: at, late_policy: 'mark', watermark_ms: 0, policy: 'drop')"),
    { ..pair_context(), inputs: [], },
  ) is Err(InvalidQuery))
}
