// Generated from independently declared public fixtures; do not edit.

///|
fn carrier_continuation_public_context() -> Context {
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "records", quoted: false, }],
        name: "records",
        source: GeneratedValues(
          from_unpivot_public_cursor(
            "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"amount\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":null},{\"id\":3,\"amount\":30}]},\"as\":\"records\"}",
          ),
        ),
        visible_fields: ["id", "amount"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn carrier_continuation_fixture_program(
  text : String,
  format : @frontend.Format,
) -> @program.Program {
  let lowered = @frontend.lower(
    text,
    format,
    Some(carrier_continuation_public_context()),
  ).unwrap()
  match lowered.program {
    Some(program) => program
    None =>
      @program.parse(
        lowered.document,
        construction_limits().program,
        format=lowered.format,
      ).unwrap()
  }
}

///|
fn carrier_continuation_fixture_schema(
  program : @program.Program,
) -> Array[@schema.Field] raise {
  let checked = match
    @check.check_parsed(
      program,
      graph_event_environment(),
      None,
      graph_rows_check_limits(),
    ) {
    Checked(checked) => checked
    Rejected(diagnostic) => {
      graph_rows_rejected(diagnostic)
      fail("rejected declared control")
    }
    NeedsInputs(_) => fail("focused control uses closed Values, not a provider")
  }
  let results = @stage_results.stage_at(
    @check.checked_stage_results(checked),
    0,
  ).unwrap()
  let result = @relation_results.lookup(results, "rows").unwrap()
  @schema.fields(@relation_results.output_schema(result))
}

///|
test "F01 F02 declared public inputs reach the normal SQL AQL-text and machine checker" {
  let expected = carrier_continuation_fixture_schema(
    carrier_continuation_fixture_program(
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.carrier_continuation_graph_events\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"node_key\":{\"type\":\"number\",\"nullable\":false},\"occurred_ms\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"node_key\":1,\"occurred_ms\":0}]},\"as\":\"rows\"},{\"graph\":{\"version\":\"actql-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"rows\",\"key\":[\"node_key\"],\"labels\":[{\"name\":\"N\",\"properties\":{\"mode\":\"columns\",\"columns\":[{\"from\":\"occurred_ms\",\"to\":\"occurred_ms\"}]}}]}],\"edges\":[]},\"as\":\"g\"},{\"from\":\"g\",\"node_rows\":true,\"as\":\"nodes\"},{\"from\":\"nodes\",\"to_events\":{\"id\":\"node_key\",\"time\":\"occurred_ms\"},\"as\":\"ev\"},{\"from\":\"ev\",\"events\":true,\"as\":\"event_rows\"},{\"from\":\"event_rows\",\"sort\":[{\"field\":\"node_key\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"node_key\",\"occurred_ms\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"node_key\",\"occurred_ms\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      @frontend.Json,
    ),
  )
  for
    (name, text, format) in [
      (
        "carrier-continuation-json-events-control",
        "{\"version\":\"actql/0.1\",\"id\":\"fixture.carrier_continuation_graph_events\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"node_key\":{\"type\":\"number\",\"nullable\":false},\"occurred_ms\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"node_key\":1,\"occurred_ms\":0}]},\"as\":\"rows\"},{\"graph\":{\"version\":\"actql-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"rows\",\"key\":[\"node_key\"],\"labels\":[{\"name\":\"N\",\"properties\":{\"mode\":\"columns\",\"columns\":[{\"from\":\"occurred_ms\",\"to\":\"occurred_ms\"}]}}]}],\"edges\":[]},\"as\":\"g\"},{\"from\":\"g\",\"node_rows\":true,\"as\":\"nodes\"},{\"from\":\"nodes\",\"to_events\":{\"id\":\"node_key\",\"time\":\"occurred_ms\"},\"as\":\"ev\"},{\"from\":\"ev\",\"events\":true,\"as\":\"event_rows\"},{\"from\":\"event_rows\",\"sort\":[{\"field\":\"node_key\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"node_key\",\"occurred_ms\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"node_key\",\"occurred_ms\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
        @frontend.Json,
      ),
      (
        "carrier-continuation-graph-marked-sql",
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) , picked AS (FROM GRAPH g) FROM picked |> node_rows() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Sql,
      ),
      (
        "carrier-continuation-graph-marked-aql-text",
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) , picked AS (FROM GRAPH g) FROM picked |> node_rows() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Text,
      ),
      (
        "carrier-continuation-graph-unmarked-sql",
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) , picked AS (FROM g) FROM picked |> node_rows() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Sql,
      ),
      (
        "carrier-continuation-graph-unmarked-aql-text",
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) , picked AS (FROM g) FROM picked |> node_rows() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Text,
      ),
      (
        "carrier-continuation-events-flat-sql",
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) FROM g |> node_rows() |> to_events(id: node_key, time: occurred_ms) |> events() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Sql,
      ),
      (
        "carrier-continuation-events-flat-aql-text",
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) FROM g |> node_rows() |> to_events(id: node_key, time: occurred_ms) |> events() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Text,
      ),
      (
        "carrier-continuation-events-with-sql",
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) , projected AS (FROM g |> node_rows()), temporal AS (FROM projected |> to_events(id: node_key, time: occurred_ms)) FROM temporal |> events() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Sql,
      ),
      (
        "carrier-continuation-events-with-aql-text",
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) , projected AS (FROM g |> node_rows()), temporal AS (FROM projected |> to_events(id: node_key, time: occurred_ms)) FROM temporal |> events() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Text,
      ),
      (
        "carrier-continuation-source-events-flat-sql",
        "WITH source_rows AS (SELECT id AS node_key, 0 AS occurred_ms FROM records WHERE id = 1), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) FROM g |> node_rows() |> to_events(id: node_key, time: occurred_ms) |> events() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Sql,
      ),
      (
        "carrier-continuation-source-events-flat-aql-text",
        "WITH source_rows AS (SELECT id AS node_key, 0 AS occurred_ms FROM records WHERE id = 1), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) FROM g |> node_rows() |> to_events(id: node_key, time: occurred_ms) |> events() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Text,
      ),
      (
        "carrier-continuation-source-events-with-sql",
        "WITH source_rows AS (SELECT id AS node_key, 0 AS occurred_ms FROM records WHERE id = 1), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) , projected AS (FROM g |> node_rows()), temporal AS (FROM projected |> to_events(id: node_key, time: occurred_ms)) FROM temporal |> events() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Sql,
      ),
      (
        "carrier-continuation-source-events-with-aql-text",
        "WITH source_rows AS (SELECT id AS node_key, 0 AS occurred_ms FROM records WHERE id = 1), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) , projected AS (FROM g |> node_rows()), temporal AS (FROM projected |> to_events(id: node_key, time: occurred_ms)) FROM temporal |> events() |> SELECT node_key, occurred_ms |> ORDER BY node_key",
        @frontend.Text,
      ),
    ] {
    let program = carrier_continuation_fixture_program(text, format)
    let actual = carrier_continuation_fixture_schema(program)
    assert_eq(
      actual.map(field => @schema.reference_name(field.name)),
      ["node_key", "occurred_ms"],
      msg=name,
    )
    for i in 0..<actual.length() {
      assert_eq(actual[i].presence, expected[i].presence, msg=name)
      assert_true(
        @contract.type_equal(actual[i].contract, expected[i].contract, 10000),
        msg=name,
      )
    }
    let wire = semantic(program)
    if name.contains("events") {
      for operation in ["node_rows", "to_events", "events"] {
        assert_eq(
          wire.split("\"" + operation + "\":").length() - 1,
          1,
          msg=name,
        )
      }
    }
    if name.contains("source-events") {
      assert_eq(wire.split("\"values\":{").length(), 2, msg=name)
      assert_true(
        wire.contains(
          "\"filter\":{\"eq\":[{\"field\":\"id\"},{\"literal\":1}]}",
        ),
        msg=name,
      )
    }
  }
}

///|
test "F01 declared explicit Graph refusals keep the authored operand cause" {
  for
    (name, text, format) in [
      (
        "carrier-continuation-refusal-demanded-events-sql",
        "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), e AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)), not_a_graph AS (FROM GRAPH e) FROM not_a_graph |> events() |> SELECT event_id",
        @frontend.Sql,
      ),
      (
        "carrier-continuation-refusal-demanded-events-aql-text",
        "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), e AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)), not_a_graph AS (FROM GRAPH e) FROM not_a_graph |> events() |> SELECT event_id",
        @frontend.Text,
      ),
      (
        "carrier-continuation-refusal-unused-events-sql",
        "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), e AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)), unused AS (FROM GRAPH e) SELECT 1 AS answer",
        @frontend.Sql,
      ),
      (
        "carrier-continuation-refusal-unused-events-aql-text",
        "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), e AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)), unused AS (FROM GRAPH e) SELECT 1 AS answer",
        @frontend.Text,
      ),
      (
        "carrier-continuation-refusal-root-events-sql",
        "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), e AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)) FROM GRAPH e |> events() |> SELECT event_id",
        @frontend.Sql,
      ),
      (
        "carrier-continuation-refusal-root-events-aql-text",
        "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), e AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)) FROM GRAPH e |> events() |> SELECT event_id",
        @frontend.Text,
      ),
      (
        "carrier-continuation-refusal-marked-relation-sql",
        "WITH source_rows AS (SELECT 1 AS event_id), unused AS (FROM GRAPH source_rows) SELECT 1 AS answer",
        @frontend.Sql,
      ),
      (
        "carrier-continuation-refusal-marked-relation-aql-text",
        "WITH source_rows AS (SELECT 1 AS event_id), unused AS (FROM GRAPH source_rows) SELECT 1 AS answer",
        @frontend.Text,
      ),
      (
        "carrier-continuation-refusal-shadowed-events-sql",
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) FROM (WITH g AS (FROM source_rows |> to_events(id: node_key, time: occurred_ms)), chosen AS (FROM GRAPH g) FROM chosen |> events() |> SELECT node_key)",
        @frontend.Sql,
      ),
      (
        "carrier-continuation-refusal-shadowed-events-aql-text",
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) FROM (WITH g AS (FROM source_rows |> to_events(id: node_key, time: occurred_ms)), chosen AS (FROM GRAPH g) FROM chosen |> events() |> SELECT node_key)",
        @frontend.Text,
      ),
    ] {
    match
      @frontend.lower(text, format, Some(carrier_continuation_public_context())) {
      Err(QueryLowering(GraphExpected(Some(origin)))) => {
        assert_eq(@origin.kind(origin), @origin.Authored, msg=name)
        assert_true(
          @origin.span(origin).end_byte > @origin.span(origin).start_byte,
          msg=name,
        )
      }
      _ => fail("Expected authored GraphExpected: " + name)
    }
  }
}

///|
test "F02 declared Graph-only tail refuses the actual Relation" {
  for
    (text, format) in [
      (
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) FROM g |> node_rows() |> edge_rows() |> SELECT node_key",
        @frontend.Sql,
      ),
      (
        "WITH source_rows AS (SELECT 1 AS node_key, 0 AS occurred_ms), g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) FROM g |> node_rows() |> edge_rows() |> SELECT node_key",
        @frontend.Text,
      ),
    ] {
    assert_true(
      @frontend.lower(text, format, Some(carrier_continuation_public_context()))
      is Err(QueryLowering(InvalidQuery)),
    )
  }
}
