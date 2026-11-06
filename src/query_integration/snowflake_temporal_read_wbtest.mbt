///|
fn snowflake_temporal_body(
  instant? : String = "1969-12-31T23:59:59.999999999Z",
) -> Bytes {
  @utf8.encode(
    "{\"statementHandle\":\"temporal-original\",\"sqlState\":\"00000\",\"resultSetMetaData\":{\"format\":\"jsonv2\",\"numRows\":2,\"rowType\":[{\"name\":\"ACCOUNT_ID\",\"type\":\"TEXT\",\"nullable\":false},{\"name\":\"ACTIVE_USERS\",\"type\":\"DATE\",\"nullable\":false},{\"name\":\"TREND\",\"type\":\"TIMESTAMP_LTZ\",\"scale\":9,\"nullable\":true}],\"partitionInfo\":[{\"rowCount\":2}]},\"data\":[[\"a1\",\"2024-02-29\",\"" +
    instant +
    "\"],[\"a2\",\"1970-01-01\",null]]}",
  )
}

///|
fn snowflake_temporal_start(
  nonce : String,
  stopped : Ref[Bool],
) -> (@snowflake_read.Read, @resources.Ledger) raise {
  let prepared = snowflake_read_preparation(temporal=true).unwrap()
  let ledger = snowflake_read_ledger(prepared, 8192L)
  let read = @snowflake_read.start_accounted_read(
    prepared,
    nonce,
    _ => stopped.val,
    ledger,
    8192L,
    4096L,
    snowflake_read_limits(),
    10,
  ).unwrap()
  (read, ledger)
}

///|
test "Snowflake temporal Source request selects UTC and fixed formats from the same original Contracts" {
  let (read, ledger) = snowflake_temporal_start("temporal-original", Ref(true))
  let statement = snowflake_statement(read)
  let request = snowflake_next(statement)
  let expected =
    #|{"parameters":{"date_output_format":"YYYY-MM-DD","multi_statement_count":"1","timestamp_ltz_output_format":"YYYY-MM-DD\"T\"HH24:MI:SS.FF9\"Z\"","timezone":"UTC"},"role":"READER","statement":"SELECT \"ACCOUNT_ID\",\"ACTIVE_USERS\",\"TREND\" FROM \"PRODUCT\".\"USAGE\".\"USAGE_30D\"","timeout":60,"warehouse":"ANALYTICS"}
  assert_eq(@snowflake_read.statement_request_body(request), Some(expected))
  @snowflake_read.attempt_statement_request(statement, request).unwrap()
  let body = snowflake_temporal_body()
  snowflake_statement_expect(
    @snowflake_read.accept_statement_response(
      statement, request, 200, body, body,
    ),
  )
  assert_true(@snowflake_read.statement_read_complete(statement))
  let captured = snowflake_capture_result(read).unwrap()
  let input = @query.captured_source_storage(
    @row_host.row_capture_source(captured).unwrap(),
    10000,
    10000,
  ).unwrap()
  assert_true(
    @execution.producer_storage_cell(input, 0, 1)
    is Some(@execution.Captured(@admitted.Date("2024-02-29"))),
  )
  assert_true(
    @execution.producer_storage_cell(input, 0, 2)
    is Some(
      @execution.Captured(@admitted.Timestamp("1969-12-31T23:59:59.999999999Z"))
    ),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake unselected temporal representation is charged but cannot capture or settle an unconfirmed transport" {
  let stopped = Ref(false)
  let (read, ledger) = snowflake_temporal_start(
    "temporal-wrong-format", stopped,
  )
  let statement = snowflake_statement(read)
  let request = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, request).unwrap()
  let body = snowflake_temporal_body(instant="1611871777123456789")
  assert_true(
    @snowflake_read.accept_statement_response(
      statement, request, 200, body, body,
    )
    is Err(_),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  assert_true(
    @snowflake_read.close_result_read(read)
    is Err(@snowflake_read.TransportUnsettled),
  )
  stopped.val = true
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake temporal output parameters follow only the original selected column Contracts" {
  for
    (column, date_output, utc_output) in [
      ("ACCOUNT_ID", false, false),
      ("ACTIVE_USERS", true, false),
      ("TREND", false, true),
    ] {
    let prepared = snowflake_read_preparation(
      query_text="SELECT " + column + " FROM snowflake.usage_30d",
      temporal=true,
      selected_fields=[column],
    ).unwrap()
    assert_eq(
      @row_host.row_acquisition_columns(
        @snowflake_read.prepared_read_acquisition(prepared),
      ),
      [column],
    )
    let ledger = snowflake_read_ledger(prepared, 8192L)
    let read = @snowflake_read.start_accounted_read(
      prepared,
      "selected-temporal-column",
      _ => true,
      ledger,
      8192L,
      4096L,
      snowflake_read_limits(),
      10,
    ).unwrap()
    let statement = snowflake_statement(read)
    let request = snowflake_next(statement)
    let body = @snowflake_read.statement_request_body(request).unwrap()
    assert_eq(body.contains("\"date_output_format\""), date_output)
    assert_eq(body.contains("\"timestamp_ltz_output_format\""), utc_output)
    assert_eq(body.contains("\"timezone\""), utc_output)
    assert_true(body.contains("\"multi_statement_count\":\"1\""))
    assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
    snowflake_assert_retired(read, ledger)
  }
}

///|
test "Snowflake final query projection does not rewrite the original physical Source carrier" {
  let prepared = snowflake_read_preparation(
    query_text="SELECT ACCOUNT_ID FROM snowflake.usage_30d",
    temporal=true,
  ).unwrap()
  assert_eq(
    @row_host.row_acquisition_columns(
      @snowflake_read.prepared_read_acquisition(prepared),
    ),
    ["ACCOUNT_ID", "ACTIVE_USERS", "TREND"],
  )
  let ledger = snowflake_read_ledger(prepared, 8192L)
  let read = @snowflake_read.start_accounted_read(
    prepared,
    "original-physical-carrier",
    _ => true,
    ledger,
    8192L,
    4096L,
    snowflake_read_limits(),
    10,
  ).unwrap()
  let request = snowflake_next(snowflake_statement(read))
  let expected =
    #|{"parameters":{"date_output_format":"YYYY-MM-DD","multi_statement_count":"1","timestamp_ltz_output_format":"YYYY-MM-DD\"T\"HH24:MI:SS.FF9\"Z\"","timezone":"UTC"},"role":"READER","statement":"SELECT \"ACCOUNT_ID\",\"ACTIVE_USERS\",\"TREND\" FROM \"PRODUCT\".\"USAGE\".\"USAGE_30D\"","timeout":60,"warehouse":"ANALYTICS"}
  assert_eq(@snowflake_read.statement_request_body(request), Some(expected))
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  snowflake_assert_retired(read, ledger)
}
