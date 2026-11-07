///|
test "BigQuery borrowed Int64 metadata bound cannot reserve or widen the original Host capture" {
  let prepared = bigquery_read_preparation().unwrap()
  let body = bigquery_body(bigquery_rows())
  let ledger = bigquery_read_ledger(prepared, body.length().to_int64())
  let acquisition = @bigquery_read.prepared_read_acquisition(prepared)
  let stopped = Ref(false)
  let run = @row_host.start_accounted_row_acquisition(
    acquisition,
    "bigquery-wide-metadata-bound",
    _ => stopped.val,
    ledger,
    body.length().to_int64(),
    4096L,
  ).unwrap()
  @row_host.begin_row_run(run, 4096, 2, 2).unwrap()
  let before = @resources.ledger_usage(ledger)
  let read = @bigquery_read.borrow_accounted_read(
    prepared,
    run,
    bigquery_job(),
    { ..bigquery_read_limits(), max_total_rows: 9223372036854775807L, },
    4,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  @bigquery_read.bind_borrowed_read_transport(read, () => stopped.val).unwrap()
  assert_eq(@bigquery_read.accept_query_page(read, None, body).unwrap(), 2)
  assert_true(@bigquery_read.result_read_complete(read))
  assert_true(
    @bigquery_read.begin_result_capture(read) is Err(@bigquery_read.BorrowedRun),
  )
  assert_true(
    @bigquery_read.advance_result_capture(read, 1)
    is Err(@bigquery_read.BorrowedRun),
  )
  assert_true(
    @bigquery_read.advance_result_capture_cleanup(read, 1)
    is Err(@bigquery_read.BorrowedRun),
  )
  assert_true(
    @bigquery_read.capture_result_read(read) is Err(@bigquery_read.BorrowedRun),
  )
  let before_cleanup = @resources.ledger_usage(ledger)
  assert_true(
    @bigquery_read.retire_borrowed_read(read)
    is Err(@bigquery_read.TransportUnsettled),
  )
  assert_eq(@resources.ledger_usage(ledger), before_cleanup)
  stopped.val = true
  @bigquery_read.retire_borrowed_read(read).unwrap()
  @row_host.finish_row_run(run).unwrap()
  assert_true(query_capture_original_row_run(run) is Ok(_))
  @row_host.close_accounted_row_run(run).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.transferred_bytes, body.length().to_int64())
  assert_eq(after.held_bytes, 0L)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
}

///|
test "BigQuery original read still refuses an unrepresentable Host capture bound before reservation" {
  let prepared = bigquery_read_preparation().unwrap()
  let ledger = bigquery_read_ledger(prepared, 4096L)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @bigquery_read.start_accounted_read(
      prepared,
      bigquery_job(),
      "bigquery-original-wide-bound",
      _ => true,
      ledger,
      4096L,
      4096L,
      { ..bigquery_read_limits(), max_total_rows: 9223372036854775807L, },
      4,
    )
    is Err(failure) &&
    @bigquery_read.read_start_failure_issue(failure)
    is @bigquery_read.InvalidLimits &&
    @bigquery_read.read_start_failure_cleanup(failure) is None,
  )
  assert_eq(@resources.ledger_usage(ledger), before)
}

///|
test "BigQuery borrowed metadata allowance does not enlarge Host row capacity" {
  let prepared = bigquery_read_preparation().unwrap()
  let body = bigquery_body(bigquery_rows())
  let ledger = bigquery_read_ledger(prepared, body.length().to_int64())
  let run = @row_host.start_accounted_row_acquisition(
    @bigquery_read.prepared_read_acquisition(prepared),
    "bigquery-original-small-capture",
    _ => true,
    ledger,
    body.length().to_int64(),
    4096L,
  ).unwrap()
  @row_host.begin_row_run(run, 4096, 2, 1).unwrap()
  let read = @bigquery_read.borrow_accounted_read(
    prepared,
    run,
    bigquery_job(),
    { ..bigquery_read_limits(), max_total_rows: 9223372036854775807L, },
    4,
  ).unwrap()
  @bigquery_read.bind_borrowed_read_transport(read, () => true).unwrap()
  assert_true(
    @bigquery_read.accept_query_page(read, None, body)
    is Err(@bigquery_read.Host(_)),
  )
  assert_false(@bigquery_read.result_read_complete(read))
  assert_true(@row_host.capture_row_run(run) is Err(_))
  @bigquery_read.retire_borrowed_read(read).unwrap()
  @row_host.close_accounted_row_run(run).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.transferred_bytes, body.length().to_int64())
  assert_eq(after.held_bytes, 0L)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
}
