///|
// This original declaration is a compiler input, not an installed Gmail issuer.
test "Gmail unchanged public thread query preserves original temporal dependencies" {
  let text = "FROM gmail.threads\n|> WHERE 'INBOX' IN UNNEST(labels) AND message_count = 1\n     AND last_message_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)\n|> SELECT id, subject, last_message_date\n|> ORDER BY last_message_date;\n"
  let declaration = @wire.admit(
    @source.parse_json(
      "{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"string\",\"nullable\":false},\"subject\":{\"type\":\"string\",\"nullable\":false},\"labels\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}},\"message_count\":{\"type\":\"int64\",\"nullable\":false},\"last_message_date\":{\"type\":\"timestamp\",\"nullable\":false}},\"primary_key\":[\"id\"]}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [
      {
        relation: [
          { value: "gmail", quoted: false, },
          { value: "threads", quoted: false, },
        ],
        name: "threads",
        source: Captured(declaration),
        visible_fields: [
          "id", "subject", "labels", "message_count", "last_message_date",
        ],
        graph_bindings: [],
      },
    ],
  }
  let actual = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @program.emit_program_source(actual, writer)
  let wire = @encode.finish(writer)
  assert_true(wire.contains("\"current_timestamp\":[]"))
  assert_true(wire.contains("\"timestamp_sub\":"))
  assert_true(wire.contains("\"literal\":\"1\""))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) =>
      fail("typed compiler declaration must retain complete input contracts")
    Rejected(error) => raise @check.diagnostic_cause(error)
  }
}
