///|
fn bigquery_signed64_fields() -> Array[Json] {
  let fields = bigquery_fields()
  fields[1] = Json::object(
    Map([
      ("name", "ACTIVE_USERS".to_json()),
      ("type", "INT64".to_json()),
      ("mode", "REQUIRED".to_json()),
    ]),
  )
  fields
}

///|
fn bigquery_signed64_preparation() -> @bigquery_read.PreparedRead raise {
  bigquery_read_preparation(
    description=Some(
      bigquery_read_description(fields=Some(bigquery_signed64_fields())),
    ),
  ).unwrap()
}

///|
test "BigQuery Signed64 crosses original checked Source RowRun and capture without rounding" {
  let fields = bigquery_signed64_fields()
  let prepared = bigquery_signed64_preparation()
  let body = bigquery_body(
    [
      bigquery_row("a1", "-9223372036854775808", "down".to_json()),
      bigquery_row("a2", "9223372036854775807", Json::null()),
    ],
    schema_fields=Some(fields),
  )
  let transfer = body.length().to_int64()
  let ledger = bigquery_read_ledger(prepared, transfer)
  guard @bigquery_read.start_accounted_read(
      prepared,
      bigquery_job(),
      "bq-signed64-capture",
      _ => true,
      ledger,
      transfer,
      4096L,
      bigquery_read_limits(),
      1,
    )
    is Ok(read) else {
    fail("BigQuery Signed64 original accounted read was refused")
  }
  assert_eq(
    bigquery_expect(@bigquery_read.accept_query_page(read, None, body)),
    2,
  )
  @bigquery_read.finish_result_read(read).unwrap()
  let capture = bigquery_capture_result(read).unwrap()
  let storage = @query.captured_source_storage(
    @row_host.row_capture_source(capture).unwrap(),
    10000,
    10000,
  ).unwrap()
  assert_true(
    @execution.producer_storage_cell(storage, 0, 1)
    is Some(@execution.Captured(@admitted.Signed64(-9223372036854775808L))),
  )
  assert_true(
    @execution.producer_storage_cell(storage, 1, 1)
    is Some(@execution.Captured(@admitted.Signed64(9223372036854775807L))),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, transfer)
  bigquery_assert_retired(read, ledger)
  assert_false(@execution.producer_storage_available(storage))
}

///|
test "BigQuery Signed64 overflow consumes the original page charge without partial Source" {
  let fields = bigquery_signed64_fields()
  let prepared = bigquery_signed64_preparation()
  let body = bigquery_body(
    [
      bigquery_row("a1", "9007199254740993", "down".to_json()),
      bigquery_row("a2", "9223372036854775808", Json::null()),
    ],
    schema_fields=Some(fields),
  )
  let transfer = body.length().to_int64()
  let ledger = bigquery_read_ledger(prepared, transfer)
  let stopped = Ref(false)
  guard @bigquery_read.start_accounted_read(
      prepared,
      bigquery_job(),
      "bq-signed64-overflow",
      _ => stopped.val,
      ledger,
      transfer,
      4096L,
      bigquery_read_limits(),
      1,
    )
    is Ok(read) else {
    fail("BigQuery Signed64 original accounted read was refused")
  }
  assert_true(@bigquery_read.accept_query_page(read, None, body) is Err(_))
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, transfer)
  assert_true(@bigquery_read.capture_result_read(read) is Err(_))
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @bigquery_read.close_result_read(read)
    is Err(@bigquery_read.TransportUnsettled),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@bigquery_read.result_read_job(read) is Some(_))
  stopped.val = true
  bigquery_assert_retired(read, ledger)
}
