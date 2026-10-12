///|
fn time_series_primary_source() -> String {
  "WITH grid AS (time_series(start: '2026-10-12T00:00:00.000Z', end: '2026-10-12T00:03:00.000Z', step: '1m')) SELECT time FROM grid ORDER BY time"
}

///|
fn time_series_primary_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.time_series_primary","stages":[{"id":"main","inputs":{},"steps":[{"time_series":{"start":"2026-10-12T00:00:00.000Z","end":"2026-10-12T00:03:00.000Z","step":"1m"},"as":"grid"},{"from":"grid","sort":[{"field":"time","dir":"asc","nulls":"first"}]},{"select":["time"],"as":"out"}],"results":{"rows":{"from":"out","fields":["time"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "adopted time series primary reaches existing common Relation generator" {
  match
    @check.check_parsed(
      time_series_primary_control(),
      graph_event_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) => fail("the generator has no source")
  }
  for format in [@frontend.Sql, @frontend.Text] {
    let lowered = @frontend.lower(
      time_series_primary_source(),
      format,
      Some({ ..pair_context(), inputs: [], }),
    ).unwrap()
    let actual = lowered.program.unwrap()
    let body = semantic(actual)
    assert_eq(body.split("\"time_series\":{").length(), 2)
    assert_true(body.contains("\"step\":\"1m\""))
    assert_true(!body.contains("\"values\":"))
    assert_true(!body.contains("\"graph\":"))
    match
      @check.check_parsed(
        actual,
        graph_event_environment(),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => graph_rows_rejected(issue)
      NeedsInputs(_) => fail("text must not acquire or invent an input")
    }
  }
}
