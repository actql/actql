///|
fn[T] snowflake_statement_expect(
  value : Result[T, @snowflake_read.StatementIssue],
) -> T raise {
  match value {
    Ok(value) => value
    Err(@snowflake_read.Read(issue)) => snowflake_expect(Err(issue))
    Err(@snowflake_read.InvalidSettings) =>
      fail("Snowflake statement: settings")
    Err(@snowflake_read.ForeignHandle) =>
      fail("Snowflake statement: foreign handle")
    Err(@snowflake_read.InvalidResponse) =>
      fail("Snowflake statement: response")
    Err(_) => fail("Snowflake statement: unexpected issue")
  }
}

///|
fn snowflake_statement(
  read : @snowflake_read.Read,
  max_requests? : Int = 8,
) -> @snowflake_read.StatementRead raise {
  snowflake_statement_expect(
    @snowflake_read.prepare_statement_read(
      read, "12345678-1234-1234-1234-123456789abc", "ANALYTICS", "READER", 60, max_requests,
      4096,
    ),
  )
}

///|
fn snowflake_pending(handle? : String = "query-original") -> Bytes {
  @utf8.encode(
    Json::object(
      Map([
        ("code", Json::string("333334")),
        ("statementHandle", Json::string(handle)),
        // The material URL is deliberately foreign: the next request must use
        // only the original handle and the installed origin, never this URL.
        ("statementStatusUrl", Json::string("https://foreign.invalid/steal")),
      ]),
    ).stringify(),
  )
}

///|
fn snowflake_next(
  statement : @snowflake_read.StatementRead,
) -> @snowflake_read.StatementRequest raise {
  snowflake_statement_expect(@snowflake_read.next_statement_request(statement)).unwrap()
}

///|
test "Snowflake SQL API same original POST status and partition preserve decimal capture" {
  let pending = snowflake_pending()
  let first = snowflake_result_body([snowflake_two_rows()[0]], parts=[1, 1])
  let next = @utf8.encode("{\"data\":[[\"a2\",\"0\",null]]}")
  let transfer = (pending.length() + first.length() + next.length()).to_int64()
  let (read, ledger) = snowflake_started_read("sql-api-partitions", transfer)
  let statement = snowflake_statement(read)
  let post = snowflake_next(statement)
  assert_eq(@snowflake_read.statement_request_method(post), "POST")
  assert_eq(@snowflake_read.statement_request_sequence(post), 0)
  assert_eq(
    @snowflake_read.statement_request_path(post),
    "/api/v2/statements?requestId=12345678-1234-1234-1234-123456789abc",
  )
  let body = @snowflake_read.statement_request_body(post).unwrap()
  assert_eq(
    body, "{\"parameters\":{\"multi_statement_count\":\"1\"},\"role\":\"READER\",\"statement\":\"SELECT \\\"ACCOUNT_ID\\\",\\\"ACTIVE_USERS\\\",\\\"TREND\\\" FROM \\\"PRODUCT\\\".\\\"USAGE\\\".\\\"USAGE_30D\\\"\",\"timeout\":60,\"warehouse\":\"ANALYTICS\"}",
  )
  @snowflake_read.attempt_statement_request(statement, post).unwrap()
  @snowflake_read.accept_statement_response(
    statement, post, 202, pending, pending,
  ).unwrap()
  assert_eq(@snowflake_read.result_read_usage(read), (0, 0L))
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  let status = snowflake_next(statement)
  assert_eq(@snowflake_read.statement_request_method(status), "GET")
  assert_eq(
    @snowflake_read.statement_request_path(status),
    "/api/v2/statements/query-original",
  )
  assert_true(@snowflake_read.statement_request_body(status) is None)
  @snowflake_read.attempt_statement_request(statement, status).unwrap()
  snowflake_statement_expect(
    @snowflake_read.accept_statement_response(
      statement, status, 200, first, first,
    ),
  )
  let partition = snowflake_next(statement)
  assert_eq(
    @snowflake_read.statement_request_path(partition),
    "/api/v2/statements/query-original?partition=1",
  )
  @snowflake_read.attempt_statement_request(statement, partition).unwrap()
  snowflake_statement_expect(
    @snowflake_read.accept_statement_response(
      statement, partition, 200, next, next,
    ),
  )
  assert_true(@snowflake_read.statement_read_complete(statement))
  assert_true(@snowflake_read.next_statement_request(statement) is Ok(None))
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, transfer)
  let captured = snowflake_capture_result(read).unwrap()
  let input = @query.captured_source_storage(
    @row_host.row_capture_source(captured).unwrap(),
    10000,
    10000,
  ).unwrap()
  assert_true(
    @execution.producer_storage_cell(input, 0, 1)
    is Some(@execution.Captured(@admitted.Decimal(decimal))) &&
    decimal.coefficient == "99999999999999999999999999999999999999",
  )
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake SQL API nominal request refuses foreign pending unattempted and repeated observations" {
  let pending = snowflake_pending()
  let (read, ledger) = snowflake_started_read("sql-api-one-shot", 4096L)
  let (foreign_read, foreign_ledger) = snowflake_started_read(
    "sql-api-foreign", 4096L,
  )
  let statement = snowflake_statement(read)
  let foreign = snowflake_statement(foreign_read)
  let request = snowflake_next(statement)
  let other_request = snowflake_next(foreign)
  assert_true(
    @snowflake_read.next_statement_request(statement)
    is Err(@snowflake_read.PendingRequest),
  )
  assert_true(
    @snowflake_read.attempt_statement_request(statement, other_request)
    is Err(@snowflake_read.WrongRequest),
  )
  assert_true(
    @snowflake_read.accept_statement_response(
      statement, request, 202, pending, pending,
    )
    is Err(@snowflake_read.NotAttempted),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  @snowflake_read.attempt_statement_request(statement, request).unwrap()
  assert_true(
    @snowflake_read.attempt_statement_request(statement, request)
    is Err(@snowflake_read.AlreadyAttempted),
  )
  @snowflake_read.accept_statement_response(
    statement, request, 202, pending, pending,
  ).unwrap()
  assert_true(
    @snowflake_read.accept_statement_response(
      statement, request, 202, pending, pending,
    )
    is Err(@snowflake_read.AlreadyObserved),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    pending.length().to_int64(),
  )
  snowflake_assert_retired(read, ledger)
  snowflake_assert_retired(foreign_read, foreign_ledger)
}

///|
test "Snowflake SQL API lost POST retains original identity and unsettled cleanup without resend" {
  let stopped = Ref(false)
  let (read, ledger) = snowflake_started_read(
    "sql-api-lost-post",
    4096L,
    stopped~,
  )
  let statement = snowflake_statement(read)
  let request = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, request).unwrap()
  assert_true(
    @snowflake_read.mark_statement_response_unknown(statement, request)
    is Err(@snowflake_read.TransportUnknown),
  )
  assert_eq(
    @snowflake_read.statement_read_request_id(statement),
    "12345678-1234-1234-1234-123456789abc",
  )
  assert_true(@snowflake_read.statement_read_handle(statement) is None)
  assert_true(
    @snowflake_read.next_statement_request(statement)
    is Err(@snowflake_read.Closed),
  )
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  assert_true(
    @snowflake_read.close_result_read(read)
    is Err(@snowflake_read.TransportUnsettled),
  )
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  stopped.val = true
  snowflake_assert_retired(read, ledger)
  assert_false(@snowflake_read.statement_read_complete(statement))
}

///|
test "Snowflake SQL API status is not an empty page and bounds repeated pending responses" {
  let pending = snowflake_pending()
  let (read, ledger) = snowflake_started_read("sql-api-pending-bound", 4096L)
  let statement = snowflake_statement(read, max_requests=2)
  for _ in 0..<2 {
    let request = snowflake_next(statement)
    @snowflake_read.attempt_statement_request(statement, request).unwrap()
    @snowflake_read.accept_statement_response(
      statement, request, 202, pending, pending,
    ).unwrap()
  }
  assert_true(
    @snowflake_read.next_statement_request(statement)
    is Err(@snowflake_read.RequestLimit),
  )
  assert_eq(@snowflake_read.result_read_usage(read), (0, 0L))
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    2L * pending.length().to_int64(),
  )
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake SQL API rejects changed handles status data and partition pending responses" {
  for variant in 0..<4 {
    let (read, ledger) = snowflake_started_read(
      "sql-api-response-" + variant.to_string(),
      4096L,
    )
    let statement = snowflake_statement(read)
    let request = snowflake_next(statement)
    @snowflake_read.attempt_statement_request(statement, request).unwrap()
    if variant == 0 {
      let body = @utf8.encode(
        "{\"code\":\"333334\",\"statementHandle\":\"query-original\",\"data\":[]}",
      )
      assert_true(
        @snowflake_read.accept_statement_response(
          statement, request, 202, body, body,
        )
        is Err(@snowflake_read.Read(@snowflake_read.Response(_))),
      )
    } else {
      if variant == 3 {
        let first = snowflake_result_body([snowflake_two_rows()[0]], parts=[
          1, 1,
        ])
        @snowflake_read.accept_statement_response(
          statement, request, 200, first, first,
        ).unwrap()
      } else {
        let pending = snowflake_pending()
        @snowflake_read.accept_statement_response(
          statement, request, 202, pending, pending,
        ).unwrap()
      }
      let next = snowflake_next(statement)
      @snowflake_read.attempt_statement_request(statement, next).unwrap()
      if variant == 1 {
        let body = snowflake_pending(handle="foreign")
        assert_true(
          @snowflake_read.accept_statement_response(
            statement, next, 202, body, body,
          )
          is Err(@snowflake_read.ForeignHandle),
        )
      } else if variant == 2 {
        let body = @utf8.encode(
          @utf8.decode(snowflake_result_body(snowflake_two_rows())).replace(
            old="query-original",
            new="foreign",
          ),
        )
        assert_true(
          @snowflake_read.accept_statement_response(
            statement, next, 200, body, body,
          )
          is Err(@snowflake_read.Read(@snowflake_read.WrongStatement)),
        )
      } else {
        let body = snowflake_pending()
        assert_true(
          @snowflake_read.accept_statement_response(
            statement, next, 202, body, body,
          )
          is Err(@snowflake_read.InvalidResponse),
        )
      }
    }
    assert_false(@snowflake_read.statement_read_complete(statement))
    assert_true(@snowflake_read.capture_result_read(read) is Err(_))
    snowflake_assert_retired(read, ledger)
  }
}

///|
test "Snowflake SQL API exact wire bytes and decoded bytes have distinct provenance" {
  let decoded = snowflake_result_body(snowflake_two_rows())
  // This is an independent decoder boundary fixture, not a gzip execution.
  let wire = @utf8.encode("physical-compressed-representation")
  let (read, ledger) = snowflake_started_read(
    "sql-api-wire",
    wire.length().to_int64(),
  )
  let statement = snowflake_statement(read)
  let request = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, request).unwrap()
  snowflake_statement_expect(
    @snowflake_read.accept_statement_response(
      statement, request, 200, wire, decoded,
    ),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    wire.length().to_int64(),
  )
  assert_eq(
    @snowflake_response.result_set_response_sha256(
      @snowflake_read.result_read_original(read).unwrap(),
    ),
    @sha.hex(decoded),
  )
  assert_true(@snowflake_read.statement_read_complete(statement))
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake SQL API invalid selection does not bind or replace the original Read" {
  let (read, ledger) = snowflake_started_read("sql-api-settings", 4096L)
  assert_true(
    @snowflake_read.prepare_statement_read(
      read, "not-a-uuid", "ANALYTICS", "READER", 60, 8, 4096,
    )
    is Err(@snowflake_read.InvalidSettings),
  )
  let statement = snowflake_statement(read)
  assert_true(
    @snowflake_read.prepare_statement_read(
      read, "12345678-1234-1234-1234-123456789abc", "ANALYTICS", "READER", 60, 8,
      4096,
    )
    is Err(@snowflake_read.AlreadyBound),
  )
  assert_true(
    @snowflake_read.accept_first_result(
      read,
      snowflake_result_body(snowflake_two_rows()),
    )
    is Err(@snowflake_read.WrongStatement),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  let request = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, request).unwrap()
  let body = @utf8.encode("{\"code\":\"error\"}")
  assert_true(
    @snowflake_read.accept_statement_response(
      statement, request, 422, body, body,
    )
    is Err(@snowflake_read.HttpRejected(422)),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake SQL API charges before decoder and refuses foreign or repeated response tickets" {
  let decoded = snowflake_result_body(snowflake_two_rows())
  let wire = @utf8.encode("bounded-compressed-input")
  let (read, ledger) = snowflake_started_read(
    "sql-api-predecode",
    wire.length().to_int64(),
  )
  let (other_read, other_ledger) = snowflake_started_read(
    "sql-api-other-response", 4096L,
  )
  let statement = snowflake_statement(read)
  let other = snowflake_statement(other_read)
  let request = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, request).unwrap()
  let response = @snowflake_read.charge_statement_response(
    statement, request, 200, wire,
  ).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    wire.length().to_int64(),
  )
  assert_eq(@snowflake_read.result_read_usage(read), (0, 0L))
  assert_true(
    @snowflake_read.next_statement_request(statement)
    is Err(@snowflake_read.PendingRequest),
  )
  assert_true(
    @snowflake_read.accept_charged_statement_response(other, response, decoded)
    is Err(@snowflake_read.WrongResponse),
  )
  assert_eq(@resources.ledger_usage(other_ledger).transferred_bytes, 0L)
  snowflake_statement_expect(
    @snowflake_read.accept_charged_statement_response(
      statement, response, decoded,
    ),
  )
  assert_true(
    @snowflake_read.accept_charged_statement_response(
      statement, response, decoded,
    )
    is Err(@snowflake_read.AlreadyObserved),
  )
  assert_true(@snowflake_read.statement_read_complete(statement))
  snowflake_assert_retired(read, ledger)
  snowflake_assert_retired(other_read, other_ledger)
}

///|
test "Snowflake SQL API bounded decoder refusal retains original transport cleanup responsibility" {
  let stopped = Ref(false)
  let wire = @utf8.encode("malformed-gzip")
  let (read, ledger) = snowflake_started_read(
    "sql-api-decoder-refusal",
    wire.length().to_int64(),
    stopped~,
  )
  let statement = snowflake_statement(read)
  let request = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, request).unwrap()
  let response = @snowflake_read.charge_statement_response(
    statement, request, 200, wire,
  ).unwrap()
  assert_true(
    @snowflake_read.reject_statement_response(statement, response)
    is Err(@snowflake_read.InvalidResponse),
  )
  assert_true(
    @snowflake_read.next_statement_request(statement)
    is Err(@snowflake_read.Closed),
  )
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  assert_true(
    @snowflake_read.close_result_read(read)
    is Err(@snowflake_read.TransportUnsettled),
  )
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  stopped.val = true
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake SQL API handle is encoded as one original path segment" {
  let (read, ledger) = snowflake_started_read("sql-api-handle-path", 4096L)
  let statement = snowflake_statement(read)
  let request = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, request).unwrap()
  let body = snowflake_pending(handle="a/b?x=1#あ%")
  @snowflake_read.accept_statement_response(statement, request, 202, body, body).unwrap()
  let next = snowflake_next(statement)
  assert_eq(
    @snowflake_read.statement_request_path(next),
    "/api/v2/statements/a%2Fb%3Fx%3D1%23%E3%81%82%25",
  )
  assert_true(@snowflake_read.statement_request_body(next) is None)
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake SQL API response loss after status retains the same original lookup handle" {
  let pending = snowflake_pending()
  let (read, ledger) = snowflake_started_read("sql-api-lost-get", 4096L)
  let statement = snowflake_statement(read)
  let post = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, post).unwrap()
  @snowflake_read.accept_statement_response(
    statement, post, 202, pending, pending,
  ).unwrap()
  let status = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, status).unwrap()
  assert_true(
    @snowflake_read.mark_statement_response_unknown(statement, status)
    is Err(@snowflake_read.TransportUnknown),
  )
  assert_eq(
    @snowflake_read.statement_read_handle(statement),
    Some("query-original"),
  )
  assert_true(
    @snowflake_read.next_statement_request(statement)
    is Err(@snowflake_read.Closed),
  )
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake SQL API non-row status still consumes the original transfer ceiling" {
  let pending = snowflake_pending()
  let (read, ledger) = snowflake_started_read(
    "sql-api-status-transfer",
    pending.length().to_int64() - 1L,
  )
  let statement = snowflake_statement(read)
  let post = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, post).unwrap()
  assert_true(
    @snowflake_read.charge_statement_response(statement, post, 202, pending)
    is Err(@snowflake_read.Read(@snowflake_read.Host(_))),
  )
  assert_eq(@snowflake_read.result_read_usage(read), (0, 0L))
  assert_true(
    @snowflake_read.next_statement_request(statement)
    is Err(@snowflake_read.Closed),
  )
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  snowflake_assert_retired(read, ledger)
}

///|
fn snowflake_path_control_refusal(handle : String) -> Unit raise {
  let stopped = Ref(false)
  let body = snowflake_pending(handle~)
  let (read, ledger) = snowflake_started_read(
    "sql-api-path-control-" + handle,
    4096L,
    stopped~,
  )
  let statement = snowflake_statement(read)
  let post = snowflake_next(statement)
  @snowflake_read.attempt_statement_request(statement, post).unwrap()
  @snowflake_read.accept_statement_response(statement, post, 202, body, body).unwrap()
  // The opaque observation is valid and already charged. The refusal belongs
  // to representability of its next transport candidate, not Catalog parsing.
  assert_eq(@snowflake_read.statement_read_handle(statement), Some(handle))
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  assert_eq(@snowflake_read.result_read_usage(read), (0, 0L))
  let candidate = @snowflake_read.next_statement_request(statement)
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  assert_true(
    @snowflake_read.close_result_read(read)
    is Err(@snowflake_read.TransportUnsettled),
  )
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  assert_eq(@snowflake_read.statement_read_handle(statement), Some(handle))
  stopped.val = true
  snowflake_assert_retired(read, ledger)
  // Close original fixture custody even when the pre-fix candidate is wrong.
  assert_true(candidate is Err(@snowflake_read.UnrepresentableHandle))
  assert_true(
    @snowflake_read.next_statement_request(statement)
    is Err(@snowflake_read.Closed),
  )
}

///|
test "Snowflake SQL API dot handle is observed but refused before physical candidate" {
  snowflake_path_control_refusal(".")
}

///|
test "Snowflake SQL API dot-dot handle is observed but refused before physical candidate" {
  snowflake_path_control_refusal("..")
}

///|
test "Snowflake SQL API dot-like opaque handles retain ordinary one-segment spelling" {
  for
    index, (handle, path) in [
      (".a", "/api/v2/statements/.a"),
      ("a.", "/api/v2/statements/a."),
      ("...", "/api/v2/statements/..."),
      ("%2E", "/api/v2/statements/%252E"),
      ("%2e%2e", "/api/v2/statements/%252e%252e"),
    ] {
    let (read, ledger) = snowflake_started_read(
      "sql-api-dot-like-" + index.to_string(),
      4096L,
    )
    let statement = snowflake_statement(read)
    let post = snowflake_next(statement)
    @snowflake_read.attempt_statement_request(statement, post).unwrap()
    let body = snowflake_pending(handle~)
    @snowflake_read.accept_statement_response(statement, post, 202, body, body).unwrap()
    let request = snowflake_next(statement)
    assert_eq(@snowflake_read.statement_request_path(request), path)
    assert_eq(@snowflake_read.statement_request_sequence(request), 1)
    snowflake_assert_retired(read, ledger)
  }
}

///|
test "Snowflake SQL API complete opaque dot handle observation needs no path candidate" {
  for index, handle in [".", ".."] {
    let (read, ledger) = snowflake_started_read(
      "sql-api-dot-complete-" + index.to_string(),
      4096L,
    )
    let statement = snowflake_statement(read)
    let post = snowflake_next(statement)
    @snowflake_read.attempt_statement_request(statement, post).unwrap()
    let body = @utf8.encode(
      @utf8.decode(snowflake_result_body(snowflake_two_rows())).replace(
        old="query-original",
        new=handle,
      ),
    )
    @snowflake_read.accept_statement_response(statement, post, 200, body, body).unwrap()
    assert_eq(@snowflake_read.statement_read_handle(statement), Some(handle))
    assert_true(@snowflake_read.statement_read_complete(statement))
    assert_true(@snowflake_read.next_statement_request(statement) is Ok(None))
    assert_true(snowflake_capture_result(read) is Ok(_))
    snowflake_assert_retired(read, ledger)
  }
}
