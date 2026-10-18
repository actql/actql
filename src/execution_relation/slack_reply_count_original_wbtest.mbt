///|
// Actual Catalog -> original typed RowRun capture -> checked/lowered predicate.
// These explicit component bounds do not supply a normal Host ReaderLoan.
test "original Slack ordinary history executes the public int64 zero predicate" {
  let history = @slack.prepare_slack_message_history(
    "C1",
    {
      max_bytes: 16384,
      max_nodes: 512,
      max_depth: 16,
      max_rows: 16,
      max_cursor_bytes: 128,
      max_value_nodes: 1024,
      max_value_text_bytes: 16384,
    },
    4,
  ).unwrap()
  let request = @slack.begin_slack_message_history(history).unwrap()
  let page = @slack.admit_slack_message_history_page(
    history,
    request,
    @utf8.encode(
      "{\"ok\":true,\"has_more\":false,\"messages\":[" +
      "{\"type\":\"message\",\"ts\":\"1.000001\",\"text\":\"original question\"}," +
      "{\"type\":\"message\",\"ts\":\"2.000000\",\"text\":\"explicit zero\",\"reply_count\":0}," +
      "{\"type\":\"message\",\"ts\":\"3.000000\",\"text\":\"explicit positive\",\"reply_count\":2}," +
      "{\"type\":\"message\",\"ts\":\"4.000000\",\"text\":\"retained parent\",\"thread_ts\":\"4.000000\"}," +
      "{\"type\":\"message\",\"ts\":\"5.000000\",\"text\":\"unknown count\",\"reply_count\":null}," +
      "{\"type\":\"message\",\"ts\":\"6.000000\"}]}",
    ),
  ).unwrap()
  assert_true(
    @slack.next_slack_message_history_request(history, page).unwrap() is None,
  )
  let schema_wire = @slack.slack_message_schema_wire(16384, 1024, 32).unwrap()
  let contract = @contract.read_checked(
    input_cursor(
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":" +
      schema_wire +
      "}",
    ),
    { max_nodes: 2048, max_depth: 32, max_text_bytes: 16384, },
  ).unwrap()
  let original_schema = @schema.from_object(contract).unwrap()
  let rows_wire = @slack.slack_message_page_rows_wire(
    page,
    @slack.slack_message_column_names(),
    16384,
    2048,
    32,
  ).unwrap()
  for
    predicate in [
      "thread_ts IS NULL AND reply_count = 0", "thread_ts IS NULL AND 0 = reply_count",
    ] {
    let checked = @pipeline.check(
      input_cursor("[{\"filter\":\"" + predicate + "\"},{\"select\":[\"id\"]}]"),
      [("messages", original_schema)],
      None,
      Some(input_cursor("\"messages\"")),
      {
        max_steps: 10,
        max_work: 100000,
        max_text_bytes: 16384,
        max_nodes: 2048,
        max_tokens: 2048,
        max_depth: 64,
      },
    ).unwrap()
    let owner = @lower.bind_parameters(
      @lower.prepare(checked, {
        max_nodes: 1000,
        max_references: 1000,
        max_work: 100000,
        max_identifier_bytes: 16384,
      }).unwrap(),
      None,
      max_parameters=0,
      max_name_bytes=0,
    ).unwrap()
    let captured = capture_input(
      owner,
      0,
      @decode.elements(input_cursor(rows_wire)).unwrap(),
      max_rows=6,
      run_limits().input_values,
    ).unwrap()
    assert_true(physical_equal(captured_owner(captured), owner))
    let sequence = prepared_sequence(owner)
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      [sequence_fragment_context(sequence, 0, 6L)],
      ["select_1"],
      100000,
      10000,
    ).unwrap()
    let completed = execute_generated_sequence(generated, [captured], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    }).unwrap()
    let output = test_row_output(completed_output(completed, Step(1)).unwrap())
    assert_eq(output.names, ["id"])
    assert_eq(output.rows.length(), 2)
    assert_true(output.rows[0][0] is Text("C1:1.000001"))
    assert_true(output.rows[1][0] is Text("C1:2.000000"))
  }
}
