///|
fn bigquery_job_row_run(
  nonce : String,
  stopped : Ref[Bool],
) -> (
  @bigquery_read.JobRead,
  @bigquery_read.Read,
  @row_host.RowRun,
  @row_host.RowAcquisition,
  @resources.Ledger,
) raise {
  let prepared = bigquery_read_preparation().unwrap()
  let acquisition = @bigquery_read.prepared_read_acquisition(prepared)
  let ledger = bigquery_read_ledger(prepared, 24000L)
  let run = @row_host.start_accounted_row_acquisition(
    acquisition,
    nonce,
    _ => stopped.val,
    ledger,
    24000L,
    4096L,
  ).unwrap()
  @row_host.begin_row_run(run, 4096, 2, 2).unwrap()
  let read = @bigquery_read.borrow_accounted_read(
    prepared,
    run,
    bigquery_job(),
    bigquery_read_limits(),
    4,
  ).unwrap()
  @bigquery_read.bind_borrowed_read_transport(read, () => stopped.val).unwrap()
  (bigquery_job_session(read), read, run, acquisition, ledger)
}

///|
test "BigQuery Job binds the nominal original RowRun and acquisition not equal routing DATA" {
  let (job, read, run, acquisition, ledger) = bigquery_job_row_run(
    "same-original-nonce",
    Ref(true),
  )
  let (foreign, foreign_read, foreign_run, foreign_acquisition, foreign_ledger) = bigquery_job_row_run(
    "same-original-nonce",
    Ref(true),
  )
  let before = @resources.ledger_usage(ledger)
  assert_eq(
    @bigquery_catalog.query_job_reference(@bigquery_read.job_read_original(job)),
    @bigquery_catalog.query_job_reference(
      @bigquery_read.job_read_original(foreign),
    ),
  )
  assert_true(@bigquery_read.job_read_matches_row_run(job, run, acquisition))
  assert_false(
    @bigquery_read.job_read_matches_row_run(job, foreign_run, acquisition),
  )
  assert_false(
    @bigquery_read.job_read_matches_row_run(job, run, foreign_acquisition),
  )
  assert_false(
    @bigquery_read.job_read_matches_row_run(foreign, run, acquisition),
  )
  assert_true(
    @bigquery_read.job_read_matches_row_run(
      foreign, foreign_run, foreign_acquisition,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // A nominal observation does not attempt the pending original POST.
  let request = bigquery_job_request(job)
  assert_eq(@bigquery_read.job_request_sequence(request), 0)
  @bigquery_read.attempt_job_request(job, request).unwrap()
  @bigquery_read.retire_borrowed_read(read).unwrap()
  assert_false(@bigquery_read.job_read_matches_row_run(job, run, acquisition))
  @row_host.close_accounted_row_run(run).unwrap()
  @bigquery_read.retire_borrowed_read(foreign_read).unwrap()
  @row_host.close_accounted_row_run(foreign_run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(
    @resources.ledger_usage(foreign_ledger).reserved_execution_bytes,
    0L,
  )
}

///|
test "BigQuery Job Unknown and closed RowRun refuse correspondence without cleanup ACK" {
  let stopped = Ref(false)
  let (job, read, run, acquisition, ledger) = bigquery_job_row_run(
    "original-unknown", stopped,
  )
  assert_true(@bigquery_read.job_read_matches_row_run(job, run, acquisition))
  let request = bigquery_job_request(job)
  @bigquery_read.attempt_job_request(job, request).unwrap()
  assert_true(
    @bigquery_read.mark_job_response_unknown(job, request)
    is Err(@bigquery_read.TransportUnknown),
  )
  assert_false(@bigquery_read.job_read_matches_row_run(job, run, acquisition))
  let before = @resources.ledger_usage(ledger)
  assert_true(@row_host.close_accounted_row_run(run) is Err(_))
  assert_false(@bigquery_read.job_read_matches_row_run(job, run, acquisition))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(before.reserved_execution_bytes > 0L)
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  @bigquery_read.retire_borrowed_read(read).unwrap()
  assert_false(@bigquery_read.job_read_matches_row_run(job, run, acquisition))
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
