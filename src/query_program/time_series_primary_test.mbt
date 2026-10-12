///|
fn time_series_primary_source() -> String {
  "WITH grid AS (time_series(start: '2026-10-12T00:00:00.000Z', end: '2026-10-12T00:03:00.000Z', step: '1m')) SELECT time FROM grid ORDER BY time"
}

///|
test "Relation generator retains a bare AQL primary and ordinary row alias" {
  let source = "time_series(start: '2026-10-12T00:00:00.000Z', end: '2026-10-12T00:03:00.000Z', step: 60000) |> AS ticks |> SELECT ticks.time AS moment |> ORDER BY moment"
  let actual = @frontend.lower(
    source,
    Text,
    Some({ ..pair_context(), inputs: [], }),
  ).unwrap().program.unwrap()
  assert_eq(semantic(actual).split("\"time_series\":{").length(), 2)
  assert_true(!semantic(actual).contains("\"values\":"))
  assert_true(!semantic(actual).contains("\"graph\":"))
  match
    @check.check_parsed(actual, graph_event_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) => fail("bare generator has no source input")
  }
}

///|
test "nearest WITH generator binding shadows an unused outer generator" {
  let source = "WITH grid AS (time_series(start: '2026-10-12T00:00:00.000Z', end: '2026-10-12T00:03:00.000Z', step: '1m')), selected AS (WITH grid AS (time_series(start: '2026-10-12T00:00:00.000Z', end: '2026-10-12T00:01:00.000Z', step: '1m')) SELECT time FROM grid) SELECT time FROM selected ORDER BY time"
  let actual = @frontend.lower(
    source,
    Sql,
    Some({ ..pair_context(), inputs: [], }),
  ).unwrap().program.unwrap()
  let body = semantic(actual)
  assert_eq(body.split("\"time_series\":{").length(), 2)
  assert_true(body.contains("2026-10-12T00:01:00.000Z"))
  assert_true(!body.contains("2026-10-12T00:03:00.000Z"))
  match
    @check.check_parsed(actual, graph_event_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) => fail("lexical generator scope does not acquire data")
  }
}

///|
test "NONE-input generator cannot silently replace a submitted Relation" {
  let source = "WITH source_rows AS (SELECT 1 AS id) FROM source_rows |> time_series(start: '2026-10-12T00:00:00.000Z', end: '2026-10-12T00:03:00.000Z', step: '1m')"
  assert_true(
    @frontend.lower(source, Text, Some({ ..pair_context(), inputs: [], }))
    is Err(QuerySyntax(_)),
  )
}

///|
test "two consumers share one generated grid without removing duplicate occurrences" {
  let text = "WITH grid AS (time_series(start: '2026-10-12T00:00:00.000Z', end: '2026-10-12T00:03:00.000Z', step: '1m')) SELECT time FROM grid UNION ALL SELECT time FROM grid ORDER BY time"
  let actual = @frontend.lower(
    text,
    Sql,
    Some({ ..pair_context(), inputs: [], }),
  ).unwrap().program.unwrap()
  let body = semantic(actual)
  assert_eq(body.split("\"time_series\":{").length(), 2)
  assert_eq(body.split("\"append\":{").length(), 2)
  assert_true(!body.contains("\"values\":"))
  match
    @check.check_parsed(actual, graph_event_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) => fail("shared generated input has no source")
  }
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
fn time_series_primary_schema(
  program : @program.Program,
) -> Array[@schema.Field] raise {
  let checked = match
    @check.check_parsed(
      program,
      graph_event_environment(),
      None,
      check_limits(),
    ) {
    Checked(checked) => checked
    Rejected(issue) => {
      graph_rows_rejected(issue)
      fail("declared series was rejected")
    }
    NeedsInputs(_) => fail("literal series has no input")
  }
  let results = @stage_results.stage_at(
    @check.checked_stage_results(checked),
    0,
  ).unwrap()
  @schema.fields(
    @relation_results.output_schema(
      @relation_results.lookup(results, "rows").unwrap(),
    ),
  )
}

///|
test "empty time-series retains its independent timestamp schema" {
  let source = time_series_primary_source().replace(
    old="00:03:00.000Z",
    new="00:00:00.000Z",
  )
  let actual = @frontend.lower(
    source,
    Sql,
    Some({ ..pair_context(), inputs: [], }),
  ).unwrap().program.unwrap()
  let expected = time_series_primary_schema(time_series_primary_control())
  let fields = time_series_primary_schema(actual)
  assert_eq(fields.map(field => field.name), expected.map(field => field.name))
  assert_eq(fields[0].presence, expected[0].presence)
  assert_true(
    @contract.type_equal(fields[0].contract, expected[0].contract, 10000),
  )
}

///|
test "time-series preserves whole Parameter roles until common binding" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"begin\":{\"type\":\"timestamp\",\"nullable\":false},\"finish\":{\"type\":\"timestamp\",\"nullable\":false},\"tick\":{\"type\":\"number\",\"nullable\":false}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 128, max_depth: 16, max_text_bytes: 4096, },
  ).unwrap()
  let text = "WITH grid AS (time_series(start: @BEGIN, end: @finish, step: @tick)) SELECT time FROM grid ORDER BY time"
  let actual = @frontend.lower(
    text,
    Sql,
    Some({
      ..pair_context(),
      inputs: [],
      parameter_declarations: Some(declarations),
    }),
  ).unwrap().program.unwrap()
  let body = semantic(actual)
  for name in ["begin", "finish", "tick"] {
    assert_true(body.contains("\"$param\":\"" + name + "\""))
  }
  assert_true(
    @check.check_parsed(actual, graph_event_environment(), None, check_limits())
    is NeedsInputs(_),
  )
  let values = from_unpivot_public_cursor(
    "{\"begin\":\"2026-10-12T00:00:00.000Z\",\"finish\":\"2026-10-12T00:03:00.000Z\",\"tick\":60000}",
  )
  match
    @check.check_parsed(
      actual,
      graph_event_environment(),
      Some(values),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) =>
      fail("supplied endpoints and step reach their existing owner")
  }
}

///|
test "unused time-series bodies retain common timestamp and range refusals" {
  for
    (start, end, reversed) in [
      ("not-a-timestamp", "2026-10-12T00:03:00.000Z", false),
      ("2026-10-12T00:03:00.000Z", "2026-10-12T00:00:00.000Z", true),
    ] {
    let text = "WITH unused AS (time_series(start: '" +
      start +
      "', end: '" +
      end +
      "', step: '1m')) SELECT 1 AS answer"
    match @frontend.lower(text, Sql, Some({ ..pair_context(), inputs: [], })) {
      Err(
        QueryLowering(
          BindingPreparation(
            SourceProgram(Program(Pipeline(_, issue)))
            | LocalProgram(Pipeline(_, issue))
          )
        )
      ) =>
        if reversed {
          assert_true(issue.kind is TimeSeries(ReversedRange))
        } else {
          assert_true(issue.kind is TimeSeries(InvalidTimestamp))
        }
      Err(QueryLowering(issue)) => {
        ignore(with_demand_program(Err(issue)))
        fail("expected a time-series refusal")
      }
      _ =>
        fail(
          "invalid unused generator must fail through the original time-series owner",
        )
    }
  }
}

///|
test "adopted time series primary reaches existing common Relation generator" {
  let expected_schema = time_series_primary_schema(
    time_series_primary_control(),
  )
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
    let actual_schema = time_series_primary_schema(actual)
    assert_eq(
      actual_schema.map(field => field.name),
      expected_schema.map(field => field.name),
    )
    for i in 0..<actual_schema.length() {
      assert_eq(actual_schema[i].presence, expected_schema[i].presence)
      assert_true(
        @contract.type_equal(
          actual_schema[i].contract,
          expected_schema[i].contract,
          10000,
        ),
      )
    }
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
