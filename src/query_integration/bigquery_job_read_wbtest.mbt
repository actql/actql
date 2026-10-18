///|
fn bigquery_job_status(
  state : String,
  job? : String = "original_job-1",
  sql? : String = "SELECT `ACCOUNT_ID`, `ACTIVE_USERS`, `TREND` FROM `acme-project`.`product`.`usage`",
  failed? : Bool = false,
) -> Bytes {
  let status = Map([("state", state.to_json())])
  if failed {
    status["errorResult"] = Json::object(
      Map([("reason", "invalidQuery".to_json())]),
    )
  }
  @utf8.encode(
    Json::object(
      Map([
        ("kind", "bigquery#job".to_json()),
        (
          "jobReference",
          Json::object(
            Map([
              ("projectId", "acme-project".to_json()),
              ("jobId", job.to_json()),
              ("location", "EU".to_json()),
            ]),
          ),
        ),
        (
          "configuration",
          Json::object(
            Map([
              (
                "query",
                Json::object(
                  Map([
                    ("query", sql.to_json()),
                    ("maximumBytesBilled", "1000000".to_json()),
                    ("useLegacySql", false.to_json()),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        ("status", Json::object(status)),
      ]),
    ).stringify(),
  )
}

///|
fn bigquery_job_session(read : @bigquery_read.Read) -> @bigquery_read.JobRead {
  @bigquery_read.prepare_job_read(read, 1000000L, 2, 0, 8, 4096).unwrap()
}

///|
fn bigquery_job_request(
  value : @bigquery_read.JobRead,
) -> @bigquery_read.JobRequest {
  @bigquery_read.next_job_request(value).unwrap().unwrap()
}

///|
fn bigquery_job_response(
  value : @bigquery_read.JobRead,
  body : Bytes,
  status? : Int = 200,
) -> Unit {
  let request = bigquery_job_request(value)
  @bigquery_read.attempt_job_request(value, request).unwrap()
  @bigquery_read.accept_job_response(value, request, status, body, body).unwrap()
}

///|
test "BigQuery same original Job POST once then status and exact cursor pages capture Common rows" {
  let (read, ledger) = bigquery_started_read("bq-job-pages", 24000L)
  let value = bigquery_job_session(read)
  assert_true(
    @bigquery_read.prepare_job_read(read, 1000000L, 2, 0, 8, 4096)
    is Err(@bigquery_read.AlreadyBound),
  )
  let post = bigquery_job_request(value)
  assert_eq(@bigquery_read.job_request_method(post), "POST")
  assert_eq(
    @bigquery_read.job_request_path(post),
    "/bigquery/v2/projects/acme-project/jobs",
  )
  let body = @bigquery_read.job_request_body(post).unwrap()
  assert_true(body.contains("\"jobId\":\"original_job-1\""))
  assert_true(body.contains("\"maximumBytesBilled\":\"1000000\""))
  @bigquery_read.attempt_job_request(value, post).unwrap()
  assert_true(
    @bigquery_read.attempt_job_request(value, post)
    is Err(@bigquery_read.AlreadyAttempted),
  )
  let running = bigquery_job_status("RUNNING")
  @bigquery_read.accept_job_response(value, post, 200, running, running).unwrap()
  let status = bigquery_job_request(value)
  assert_eq(@bigquery_read.job_request_method(status), "GET")
  assert_eq(
    @bigquery_read.job_request_path(status),
    "/bigquery/v2/projects/acme-project/jobs/original_job-1?location=EU",
  )
  @bigquery_read.attempt_job_request(value, status).unwrap()
  let done = bigquery_job_status("DONE")
  @bigquery_read.accept_job_response(value, status, 200, done, done).unwrap()
  assert_true(@bigquery_read.job_read_remote_done(value))
  let first_request = bigquery_job_request(value)
  assert_eq(
    @bigquery_read.job_request_path(first_request),
    "/bigquery/v2/projects/acme-project/queries/original_job-1?location=EU&maxResults=2&timeoutMs=0",
  )
  @bigquery_read.attempt_job_request(value, first_request).unwrap()
  let rows = bigquery_rows()
  let first = bigquery_body([rows[0]], token=Some("next/opaque+token"))
  @bigquery_read.accept_job_response(value, first_request, 200, first, first).unwrap()
  assert_true(@bigquery_read.capture_result_read(read) is Err(_))
  let second_request = bigquery_job_request(value)
  assert_true(
    @bigquery_read.job_request_path(second_request).has_suffix(
      "&pageToken=next%2Fopaque%2Btoken",
    ),
  )
  @bigquery_read.attempt_job_request(value, second_request).unwrap()
  let second = bigquery_body([rows[1]])
  @bigquery_read.accept_job_response(value, second_request, 200, second, second).unwrap()
  assert_true(@bigquery_read.job_read_complete(value))
  assert_true(@bigquery_read.next_job_request(value) is Ok(None))
  assert_eq(@bigquery_read.result_read_usage(read), (2, 2L))
  let captured = @bigquery_read.capture_result_read(read).unwrap()
  assert_true(@row_host.row_capture_source(captured) is Ok(_))
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    (running.length() + done.length() + first.length() + second.length()).to_int64(),
  )
  bigquery_assert_retired(read, ledger)
}

///|
test "BigQuery accepted running Job then HTTP403 is not remote termination or a POST retry" {
  let (read, ledger) = bigquery_started_read("bq-running-refused", 24000L)
  let value = bigquery_job_session(read)
  bigquery_job_response(value, bigquery_job_status("RUNNING"))
  let request = bigquery_job_request(value)
  @bigquery_read.attempt_job_request(value, request).unwrap()
  let denied = @utf8.encode("{\"error\":{\"code\":403}}")
  assert_true(
    @bigquery_read.accept_job_response(value, request, 403, denied, denied)
    is Err(@bigquery_read.HttpRejected(403)),
  )
  assert_false(@bigquery_read.job_read_remote_done(value))
  assert_true(
    @bigquery_read.next_job_request(value) is Err(@bigquery_read.Closed),
  )
  assert_true(@bigquery_read.capture_result_read(read) is Err(_))
  assert_eq(
    @bigquery_catalog.query_job_reference(
      @bigquery_read.job_read_original(value),
    ),
    ("acme-project", "original_job-1", "EU"),
  )
  bigquery_assert_retired(read, ledger)
  assert_false(@bigquery_read.job_read_remote_done(value))
}

///|
test "BigQuery lost POST response keeps original and pending cleanup without any resend" {
  let stopped = Ref(false)
  let (read, ledger) = bigquery_started_read("bq-lost-post", 24000L, stopped~)
  let value = bigquery_job_session(read)
  let request = bigquery_job_request(value)
  @bigquery_read.attempt_job_request(value, request).unwrap()
  assert_true(
    @bigquery_read.mark_job_response_unknown(value, request)
    is Err(@bigquery_read.TransportUnknown),
  )
  assert_true(
    @bigquery_read.next_job_request(value) is Err(@bigquery_read.Closed),
  )
  assert_true(
    @bigquery_read.close_result_read(read)
    is Err(@bigquery_read.TransportUnsettled),
  )
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  assert_false(@bigquery_read.job_read_remote_done(value))
  stopped.val = true
  bigquery_assert_retired(read, ledger)
  assert_eq(
    @bigquery_catalog.query_job_reference(
      @bigquery_read.job_read_original(value),
    ).1,
    "original_job-1",
  )
}

///|
test "BigQuery foreign Job or altered original query configuration cannot advance the read" {
  for
    body in [
      bigquery_job_status("DONE", job="foreign_job"),
      bigquery_job_status("DONE", sql="SELECT 1"),
    ] {
    let (read, ledger) = bigquery_started_read("bq-foreign-job", 24000L)
    let value = bigquery_job_session(read)
    let request = bigquery_job_request(value)
    @bigquery_read.attempt_job_request(value, request).unwrap()
    assert_true(
      @bigquery_read.accept_job_response(value, request, 200, body, body)
      is Err(
        @bigquery_read.Read(
          @bigquery_read.Page(@bigquery_catalog.ForeignQueryJob)
        )
      ),
    )
    assert_false(@bigquery_read.job_read_remote_done(value))
    assert_true(@bigquery_read.capture_result_read(read) is Err(_))
    bigquery_assert_retired(read, ledger)
  }
}

///|
test "BigQuery DONE with final error ends remote execution without successful Source capture" {
  let (read, ledger) = bigquery_started_read("bq-done-error", 24000L)
  let value = bigquery_job_session(read)
  let request = bigquery_job_request(value)
  @bigquery_read.attempt_job_request(value, request).unwrap()
  let body = bigquery_job_status("DONE", failed=true)
  assert_true(
    @bigquery_read.accept_job_response(value, request, 200, body, body)
    is Err(@bigquery_read.ProviderFailed),
  )
  assert_true(@bigquery_read.job_read_remote_done(value))
  assert_false(@bigquery_read.job_read_complete(value))
  assert_true(@bigquery_read.capture_result_read(read) is Err(_))
  bigquery_assert_retired(read, ledger)
}

///|
test "BigQuery wire charge precedes decode and rejects foreign response and direct page bypass" {
  let (read, ledger) = bigquery_started_read("bq-wire-charge", 24000L)
  let value = bigquery_job_session(read)
  let (foreign_read, foreign_ledger) = bigquery_started_read(
    "bq-foreign-ticket", 24000L,
  )
  let foreign = bigquery_job_session(foreign_read)
  let request = bigquery_job_request(value)
  assert_true(
    @bigquery_read.charge_job_response(value, request, 200, b"wire")
    is Err(@bigquery_read.NotAttempted),
  )
  @bigquery_read.attempt_job_request(value, request).unwrap()
  let response = @bigquery_read.charge_job_response(
    value, request, 200, b"wire",
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 4L)
  assert_true(
    @bigquery_read.accept_charged_job_response(
      foreign,
      response,
      bigquery_job_status("DONE"),
    )
    is Err(@bigquery_read.WrongResponse),
  )
  @bigquery_read.accept_charged_job_response(
    value,
    response,
    bigquery_job_status("DONE"),
  ).unwrap()
  assert_true(
    @bigquery_read.accept_charged_job_response(
      value,
      response,
      bigquery_job_status("DONE"),
    )
    is Err(@bigquery_read.AlreadyObserved),
  )
  assert_true(
    @bigquery_read.accept_query_page(read, None, bigquery_body(bigquery_rows()))
    is Err(@bigquery_read.Closed),
  )
  @bigquery_read.interrupt_result_read(read)
  bigquery_assert_retired(read, ledger)
  bigquery_assert_retired(foreign_read, foreign_ledger)
}

///|
test "BigQuery request bound terminates pending status without making a new Job" {
  let (read, ledger) = bigquery_started_read("bq-request-bound", 24000L)
  let value = @bigquery_read.prepare_job_read(read, 1000000L, 2, 0, 1, 4096).unwrap()
  bigquery_job_response(value, bigquery_job_status("RUNNING"))
  assert_true(
    @bigquery_read.next_job_request(value) is Err(@bigquery_read.RequestLimit),
  )
  assert_false(@bigquery_read.job_read_remote_done(value))
  bigquery_assert_retired(read, ledger)
}
