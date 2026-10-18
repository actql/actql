///|
fn bigquery_record_limits() -> @bigquery_read.JobRecordLimits {
  {
    max_bytes: 8192,
    max_nodes: 64,
    max_depth: 8,
    max_job_bytes: 1024,
    max_material_bytes: 4096,
  }
}

///|
fn bigquery_record_wire(
  body? : String = "original body",
  job? : String = "original_job-1",
) -> String {
  // This independent vector is not obtained from the record emitter.
  "{\"body\":" +
  body.to_json().stringify() +
  ",\"format\":\"actql.bigquery-job-original/0.1\",\"jobId\":" +
  job.to_json().stringify() +
  ",\"location\":\"EU\",\"method\":\"POST\",\"path\":\"/bigquery/v2/projects/acme-project/jobs\",\"project\":\"acme-project\"}"
}

///|
test "BigQuery original record issuer precedes the same nominal POST without attempting it" {
  let (read, ledger) = bigquery_started_read("bq-original-record", 24000L)
  let session = bigquery_job_session(read)
  let limits = bigquery_record_limits()
  let record = @bigquery_read.job_original_record(session, limits).unwrap()
  let request = bigquery_job_request(session)
  let expected = "{\"configuration\":{\"query\":{\"maximumBytesBilled\":\"1000000\",\"query\":\"SELECT `ACCOUNT_ID`, `ACTIVE_USERS`, `TREND` FROM `acme-project`.`product`.`usage`\",\"useLegacySql\":false}},\"jobReference\":{\"jobId\":\"original_job-1\",\"location\":\"EU\",\"projectId\":\"acme-project\"}}"
  assert_eq(@bigquery_read.job_request_body(request), Some(expected))
  assert_eq(
    @bigquery_read.job_original_record_wire(record),
    bigquery_record_wire(body=expected),
  )
  assert_true(
    @bigquery_read.job_original_record_matches_request(session, request, record),
  )
  assert_eq(
    @bigquery_read.job_original_record_material(record),
    (
      "acme-project", "original_job-1", "EU", "POST", "/bigquery/v2/projects/acme-project/jobs",
      expected,
    ),
  )
  let cold = @bigquery_read.read_job_original_record(
    @utf8.encode(@bigquery_read.job_original_record_wire(record)),
    limits,
  ).unwrap()
  assert_true(
    @bigquery_read.job_original_record_matches_request(session, request, cold),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  @bigquery_read.attempt_job_request(session, request).unwrap()
  assert_true(
    @bigquery_read.job_original_record(session, limits)
    is Err(@bigquery_read.NotOriginalSubmit),
  )
  assert_false(
    @bigquery_read.job_original_record_matches_request(session, request, cold),
  )
  assert_true(
    @bigquery_read.attempt_job_request(session, request)
    is Err(@bigquery_read.AlreadyAttempted),
  )
  assert_true(
    @bigquery_read.mark_job_response_unknown(session, request)
    is Err(@bigquery_read.TransportUnknown),
  )
  assert_true(
    @bigquery_read.job_original_record(session, limits)
    is Err(@bigquery_read.Closed),
  )
  assert_true(
    @bigquery_read.next_job_request(session) is Err(@bigquery_read.Closed),
  )
  bigquery_assert_retired(read, ledger)
}

///|
test "BigQuery cold original record retains exact body text and is DATA not Job custody" {
  let limits = bigquery_record_limits()
  let body = "  {\"query\":\"SELECT 'é😀\\n'\",\"x\":null}  "
  let wire = bigquery_record_wire(body~)
  let cold = @bigquery_read.read_job_original_record(@utf8.encode(wire), limits).unwrap()
  assert_eq(@bigquery_read.job_original_record_wire(cold), wire)
  let (read, ledger) = bigquery_started_read("bq-original-cold", 24000L)
  let session = bigquery_job_session(read)
  let request = bigquery_job_request(session)
  // Parsing valid closed DATA cannot assert that its unrelated body was sent
  // or belongs to this live acquisition's original request.
  assert_false(
    @bigquery_read.job_original_record_matches_request(session, request, cold),
  )
  assert_eq(@bigquery_read.job_request_sequence(request), 0)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  assert_false(@bigquery_read.job_read_remote_done(session))
  bigquery_assert_retired(read, ledger)
}

///|
test "BigQuery original record cannot replace foreign nominal requests or alter exact material" {
  let (read, ledger) = bigquery_started_read("bq-original-local", 24000L)
  let (foreign_read, foreign_ledger) = bigquery_started_read(
    "bq-original-foreign", 24000L,
  )
  let session = bigquery_job_session(read)
  let foreign = bigquery_job_session(foreign_read)
  let record = @bigquery_read.job_original_record(
    session,
    bigquery_record_limits(),
  ).unwrap()
  let request = bigquery_job_request(session)
  let foreign_request = bigquery_job_request(foreign)
  assert_false(
    @bigquery_read.job_original_record_matches_request(
      session, foreign_request, record,
    ),
  )
  assert_false(
    @bigquery_read.job_original_record_matches_request(foreign, request, record),
  )
  let wrong_job = @bigquery_read.read_job_original_record(
    @utf8.encode(bigquery_record_wire(job="different_job")),
    bigquery_record_limits(),
  ).unwrap()
  assert_false(
    @bigquery_read.job_original_record_matches_request(
      session, request, wrong_job,
    ),
  )
  assert_true(
    @bigquery_read.job_original_record_matches_request(session, request, record),
  )
  bigquery_assert_retired(read, ledger)
  bigquery_assert_retired(foreign_read, foreign_ledger)
}

///|
test "BigQuery original record closed fields reject unknown revision variants duplicates and omissions" {
  let original = bigquery_record_wire()
  for
    invalid in [
      original.replace(old="/0.1", new="/0.2"),
      original.replace(old="\"method\":\"POST\"", new="\"method\":\"GET\""),
      original.replace(old="\"jobId\":\"original_job-1\"", new="\"jobId\":null"),
      original.replace(old="\"jobId\":\"original_job-1\"", new="\"jobId\":true"),
      original.replace(old="\"jobId\":\"original_job-1\"", new="\"jobId\":1"),
      original.replace(old="\"location\":\"EU\",", new=""),
      original.replace(
        old="\"body\":\"original body\"",
        new="\"body\":\"original body\",\"extra\":false",
      ),
      original.replace(
        old="\"body\":\"original body\"",
        new="\"body\":\"original body\",\"body\":\"other\"",
      ),
      original.replace(old="acme-project/jobs", new="other/jobs"),
      original.replace(old="original_job-1", new="unsafe/job"),
    ] {
    assert_true(
      @bigquery_read.read_job_original_record(
        @utf8.encode(invalid),
        bigquery_record_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "BigQuery original record limits independently bound envelope tree identity and request bytes" {
  let wire = @utf8.encode(bigquery_record_wire())
  let limits = bigquery_record_limits()
  assert_true(
    @bigquery_read.read_job_original_record(wire, {
      ..limits,
      max_bytes: wire.length() - 1,
    })
    is Err(@bigquery_read.Limit),
  )
  assert_true(
    @bigquery_read.read_job_original_record(wire, { ..limits, max_nodes: 1, })
    is Err(@bigquery_read.Limit),
  )
  assert_true(
    @bigquery_read.read_job_original_record(wire, { ..limits, max_depth: 0, })
    is Err(_),
  )
  assert_true(
    @bigquery_read.read_job_original_record(wire, {
      ..limits,
      max_job_bytes: 1,
    })
    is Err(@bigquery_read.InvalidRecord),
  )
  assert_true(
    @bigquery_read.read_job_original_record(wire, {
      ..limits,
      max_material_bytes: 1,
    })
    is Err(@bigquery_read.Limit),
  )
  assert_true(
    @bigquery_read.read_job_original_record(wire, { ..limits, max_bytes: 0, })
    is Err(@bigquery_read.InvalidLimits),
  )
  assert_true(
    @bigquery_read.read_job_original_record(b"\xff", limits)
    is Err(@bigquery_read.InvalidRecord),
  )
}
