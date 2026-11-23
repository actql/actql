///|
fn snowflake_host_run(
  nonce : String,
) -> (@snowflake_read.PreparedRead, @row_host.RowRun, @resources.Ledger) raise {
  let prepared = snowflake_read_preparation().unwrap()
  let acquisition = @snowflake_read.prepared_read_acquisition(prepared)
  let ledger = snowflake_read_ledger(prepared, 8192L)
  // This is a controlled Common evidence observer, not a physical TLS ACK.
  let run = @row_host.start_accounted_row_acquisition(
    acquisition,
    nonce,
    _ => true,
    ledger,
    8192L,
    4096L,
  ).unwrap()
  @row_host.begin_row_run(run, 4096, 2, 2).unwrap()
  (prepared, run, ledger)
}

///|
fn snowflake_host_borrow(
  prepared : @snowflake_read.PreparedRead,
  run : @row_host.RowRun,
  stopped : Ref[Bool],
  checks : Ref[Int],
) -> @snowflake_read.Read {
  let borrow = @row_host.borrow_row_run_responses(
    run,
    @snowflake_read.prepared_read_acquisition(prepared),
  ).unwrap()
  let active = Ref(None)
  let retired = Ref(false)
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => {
    if retired.val {
      return true
    }
    checks.val += 1
    if stopped.val &&
      active.val is Some(read) &&
      @snowflake_read.retire_managed_read(read) {
      retired.val = true
      active.val = None
    }
    retired.val
  }).unwrap()
  let read = @snowflake_read.adopt_managed_read(
    snowflake_read_description(),
    borrow,
    snowflake_read_limits(),
    snowflake_description_limits(),
    10,
  ).unwrap()
  active.val = Some(read)
  read
}

///|
fn snowflake_accept_host_response(
  run : @row_host.RowRun,
  statement : @snowflake_read.StatementRead,
  request : @snowflake_read.StatementRequest,
  body : Bytes,
) -> Unit raise {
  let charge = @row_host.charge_row_run_page(run, body).unwrap()
  let response = @snowflake_read.adopt_statement_response(
    statement, request, 200, charge,
  ).unwrap()
  @snowflake_read.accept_charged_statement_response(statement, response, body).unwrap()
  assert_true(
    @snowflake_read.adopt_statement_response(statement, request, 200, charge)
    is Err(@snowflake_read.WrongResponse),
  )
}

///|
fn snowflake_host_closed(
  run : @row_host.RowRun,
  ledger : @resources.Ledger,
) -> Unit raise {
  @row_host.close_accounted_row_run(run).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "Snowflake installed response borrows the same run but cannot finish capture or close it" {
  let (prepared, run, ledger) = snowflake_host_run("snowflake-host-capture")
  let checks = Ref(0)
  let stopped = Ref(true)
  let read = snowflake_host_borrow(prepared, run, stopped, checks)
  let statement = snowflake_statement(read)
  let request = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, request).unwrap()
  let body = snowflake_result_body(snowflake_two_rows())
  snowflake_accept_host_response(run, statement, request, body)
  assert_true(@snowflake_read.statement_read_complete(statement))
  assert_true(
    @snowflake_read.finish_result_read(read) is Err(@snowflake_read.BorrowedRun),
  )
  assert_true(
    @snowflake_read.begin_result_capture(read)
    is Err(@snowflake_read.BorrowedRun),
  )
  assert_true(
    @snowflake_read.advance_result_capture(read, 1)
    is Err(@snowflake_read.BorrowedRun),
  )
  assert_true(
    @snowflake_read.advance_result_capture_cleanup(read, 1)
    is Err(@snowflake_read.BorrowedRun),
  )
  assert_true(
    @snowflake_read.capture_result_read(read)
    is Err(@snowflake_read.BorrowedRun),
  )
  assert_true(
    @snowflake_read.close_result_read(read) is Err(@snowflake_read.BorrowedRun),
  )
  assert_eq(checks.val, 0)
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  assert_true(@snowflake_read.retire_managed_read(read))
  assert_eq(checks.val, 0)
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  // Exactly one Common finish and capture remains with the original Host.
  @row_host.finish_row_run(run).unwrap()
  let captured = query_capture_original_row_run(run).unwrap()
  let source = @row_host.row_capture_source(captured).unwrap()
  let input = @query.captured_source_storage(source, 10000, 10000).unwrap()
  assert_true(
    @execution.producer_storage_cell(input, 0, 1)
    is Some(@execution.Captured(@admitted.Decimal(decimal))) &&
    decimal.coefficient == "99999999999999999999999999999999999999",
  )
  snowflake_host_closed(run, ledger)
  assert_eq(checks.val, 1)
  assert_false(@execution.producer_storage_available(input))
}

///|
test "Snowflake installed response refuses foreign and repeated original run borrows" {
  let (prepared, run, ledger) = snowflake_host_run("snowflake-host-nominal")
  let independent = snowflake_read_preparation().unwrap()
  assert_true(
    @row_host.borrow_row_run_responses(
      run,
      @snowflake_read.prepared_read_acquisition(independent),
    )
    is Err(@row_host.ForeignDeclaration),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  let acquisition = @snowflake_read.prepared_read_acquisition(prepared)
  let borrow = @row_host.borrow_row_run_responses(run, acquisition).unwrap()
  assert_true(
    @row_host.borrow_row_run_responses(run, acquisition)
    is Err(@row_host.InvalidState),
  )
  assert_true(
    @snowflake_read.adopt_managed_read(
      snowflake_read_description(),
      borrow,
      snowflake_read_limits(),
      snowflake_description_limits(),
      10,
    )
    is Err(@snowflake_read.BorrowedRun),
  )
  snowflake_host_closed(run, ledger)
  assert_true(
    @row_host.borrow_row_run_responses(run, acquisition)
    is Err(@row_host.InvalidState),
  )
}

///|
test "Snowflake installed failed physical cleanup keeps the same original root and retires aliases before release" {
  let (prepared, run, ledger) = snowflake_host_run(
    "snowflake-host-pending-stop",
  )
  let checks = Ref(0)
  let stopped = Ref(false)
  let read = snowflake_host_borrow(prepared, run, stopped, checks)
  let statement = snowflake_statement(read)
  let post = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, post).unwrap()
  let body = snowflake_result_body(snowflake_two_rows())
  snowflake_accept_host_response(run, statement, post, body)
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  assert_true(
    @row_host.close_accounted_row_run(run) is Err(@row_host.Evidence(_)),
  )
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  assert_true(@snowflake_read.result_read_original(read) is None)
  assert_true(
    @snowflake_read.next_statement_request(statement)
    is Err(@snowflake_read.Closed),
  )
  stopped.val = true
  snowflake_host_closed(run, ledger)
  let observed = checks.val
  assert_true(@snowflake_read.retire_managed_read(read))
  snowflake_host_closed(run, ledger)
  assert_eq(checks.val, observed)
}

///|
test "Snowflake installed lost response keeps its original identity through parent cleanup" {
  let (prepared, run, ledger) = snowflake_host_run("snowflake-host-unknown")
  let stopped = Ref(false)
  let checks = Ref(0)
  let read = snowflake_host_borrow(prepared, run, stopped, checks)
  let statement = snowflake_statement(read)
  let post = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, post).unwrap()
  assert_true(
    @snowflake_read.mark_statement_response_unknown(statement, post)
    is Err(@snowflake_read.TransportUnknown),
  )
  assert_true(@row_host.close_accounted_row_run(run) is Err(_))
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  assert_eq(
    @snowflake_read.statement_read_request_id(statement),
    "12345678-1234-1234-1234-123456789abc",
  )
  assert_true(
    @snowflake_read.next_statement_request(statement)
    is Err(@snowflake_read.Closed),
  )
  assert_true(@row_host.capture_row_run(run) is Err(_))
  stopped.val = true
  snowflake_host_closed(run, ledger)
  assert_eq(
    @snowflake_read.statement_read_request_id(statement),
    "12345678-1234-1234-1234-123456789abc",
  )
}

///|
test "Snowflake installed response rejects unaccounted and pre-begin runs without a fallback" {
  let prepared = snowflake_read_preparation().unwrap()
  let acquisition = @snowflake_read.prepared_read_acquisition(prepared)
  let unaccounted = @row_host.start_row_acquisition(
    acquisition,
    "unaccounted",
    _ => true,
  ).unwrap()
  @row_host.begin_row_run(unaccounted, 4096, 2, 2).unwrap()
  assert_true(
    @row_host.borrow_row_run_responses(unaccounted, acquisition)
    is Err(@row_host.InvalidState),
  )
  @row_host.close_row_run(unaccounted)
  let ledger = snowflake_read_ledger(prepared, 8192L)
  let pending = @row_host.start_accounted_row_acquisition(
    acquisition,
    "pending",
    _ => true,
    ledger,
    8192L,
    4096L,
  ).unwrap()
  assert_true(
    @row_host.borrow_row_run_responses(pending, acquisition)
    is Err(@row_host.InvalidState),
  )
  snowflake_host_closed(pending, ledger)
}

///|
test "Snowflake installed physical observer is bound once to the original response borrower" {
  let (prepared, run, ledger) = snowflake_host_run("snowflake-host-observer")
  let first = Ref(0)
  let read = snowflake_host_borrow(prepared, run, Ref(true), first)
  assert_true(
    @row_host.borrow_row_run_responses(
      run,
      @snowflake_read.prepared_read_acquisition(prepared),
    )
    is Err(@row_host.InvalidState),
  )
  assert_eq(first.val, 0)
  snowflake_host_closed(run, ledger)
  assert_eq(first.val, 1)
  assert_true(
    @snowflake_read.prepare_statement_read(
      read, "12345678-1234-1234-1234-123456789abc", "ANALYTICS", "READER", 60, 8,
      4096,
    )
    is Err(@snowflake_read.Closed),
  )
}
