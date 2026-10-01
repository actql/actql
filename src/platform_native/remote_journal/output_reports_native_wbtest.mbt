///|
fn report_fixture(
  request : @remote.DispatchRequest,
  occurrence : String,
) -> @remote.RemoteOutputReportCustody {
  let c = fn(fill : String) { "sha256:" + fill.repeat(64) }
  let intent = @remote.prepare_remote_output_intent(request, {
    store_authority_cid: c("5"),
    publication_attempt_cid: c("6"),
    result_definition_cid: c("7"),
    ordering_evidence_cid: c("8"),
    coordinator_authority: "native-coordinator",
    transfer_attempt: occurrence,
    transfer_route: @transfer.DirectStream,
    destination_site_key: "destination",
    destination_site_generation: 1,
    transfer_max_bytes: 1048576L,
    transfer_expires_unix_ms: 4102444800000L,
    source_grant_cid: c("9"),
    destination_grant_cid: c("a"),
    route_capability_cid: c("b"),
    transfer_origin: "https://destination.invalid",
  }).unwrap()
  let output = @remote.admit_remote_poll_output_json(
    @remote.remote_poll_output_json(request, intent).unwrap(),
  ).unwrap()
  let manifest = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    c("1"),
    c("2"),
    c("3"),
    2,
    [c("d")],
    [12L],
    [2],
    4,
    4096,
    12L,
  ).unwrap()
  let payload = @payload.prepare_publication_payload_request(
    c("5"),
    c("6"),
    c("c"),
    c("7"),
    c("2"),
    c("1"),
    c("8"),
    c("3"),
    12L,
    2L,
  ).unwrap()
  let transfer = @transfer.prepare_request(
    "native-coordinator",
    occurrence,
    @transfer.DirectStream,
    "native-site",
    4,
    "destination",
    1,
    c("c"),
    manifest,
    1048576L,
    4102444800000L,
    c("9"),
    c("a"),
    c("b"),
  ).unwrap()
  let record = @transfer.open_record(transfer)
  @transfer.commit_transition(@transfer.prepare_start(record).unwrap(), true).unwrap()
  |> ignore
  @transfer.commit_transition(
    @transfer.prepare_source_settled(record, true, false).unwrap(),
    true,
  ).unwrap()
  |> ignore
  @transfer.commit_transition(
    @transfer.prepare_destination_commit(record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  let result = @remote.prepare_remote_output_result(
    output,
    payload,
    c("e"),
    record,
  ).unwrap()
  @remote.prepare_remote_output_report_custody(
    output, payload, transfer, result,
  ).unwrap()
}

///|
test "native report custody survives cleanup, reopen, refusal and exact ACK" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    fail("real SQLite library is required")
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    fail("real SQLite root is required")
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root + "/reports-" + @env.now().to_string() + ".sqlite3"
  let open = fn() {
    open_journal(library, database_path, 2097152L, test_control(test_site())).unwrap()
  }
  let journal = open()
  let request = test_request("report-custody")
  journal.accept(request).unwrap() |> ignore
  let custody = report_fixture(request, "transfer-report")
  let key = @remote.remote_output_report_custody_key(custody)
  let body = @remote.remote_output_report_custody_json(custody)
  journal.retain_output_report(custody).unwrap()
  journal.retain_output_report(custody).unwrap()
  journal.retain_output_intent("cleanup", "original-cleanup").unwrap()
  journal.complete_output_intent("cleanup").unwrap()
  assert_eq(journal.pending_output_intents().unwrap().length(), 0)
  assert_true(journal.close())
  let reopened = open()
  let (restored, pending) = reopened.output_report(key).unwrap()
  assert_eq(@remote.remote_output_report_custody_json(restored), body)
  assert_eq(pending, None)
  let result = @remote.remote_output_report_custody_result(custody)
  // A failed ACK commit leaves the report pending; a bare transport success
  // must never be inferred from the physical release or an in-memory retry.
  let lock = library.open_database(database_path, 2097152L).unwrap()
  lock.begin_immediate().unwrap()
  let ack_probe = @remote.remote_output_report_reply_json(
    result,
    @remote.RemoteOutputReportReply::Accepted,
  ).unwrap()
  assert_true(reopened.record_output_report_reply(key, ack_probe) is Err(_))
  assert_eq(reopened.output_report(key).unwrap().1, None)
  lock.rollback().unwrap()
  lock.close()
  let refused = @remote.remote_output_report_reply_json(
    result,
    @remote.RemoteOutputReportReply::Refused("report_conflict"),
  ).unwrap()
  reopened.record_output_report_reply(key, refused).unwrap()
  assert_true(reopened.close())
  let retry = open()
  assert_eq(
    retry.output_report(key).unwrap().1,
    Some(@remote.RemoteOutputReportReply::Refused("report_conflict")),
  )
  retry.retry_output_report(key).unwrap()
  assert_eq(
    retry.output_report(key).unwrap().1,
    Some(@remote.RemoteOutputReportReply::Retry("report_conflict")),
  )
  assert_true(
    retry.record_output_report_reply(key, "{\"accepted\":true}") is Err(_),
  )
  assert_eq(
    retry.output_report(key).unwrap().1,
    Some(@remote.RemoteOutputReportReply::Retry("report_conflict")),
  )
  let ack = @remote.remote_output_report_reply_json(
    result,
    @remote.RemoteOutputReportReply::Accepted,
  ).unwrap()
  retry.record_output_report_reply(key, ack).unwrap()
  retry.record_output_report_reply(key, ack).unwrap()
  assert_true(retry.retry_output_report(key) is Err(StateCollision))
  assert_true(
    retry.record_output_report_reply(key, refused) is Err(StateCollision),
  )
  assert_true(retry.close())
  let confirmed = open()
  assert_eq(
    confirmed.output_report(key).unwrap().1,
    Some(@remote.RemoteOutputReportReply::Accepted),
  )
  assert_eq(
    @remote.remote_output_report_custody_json(
      confirmed.output_report(key).unwrap().0,
    ),
    body,
  )
  assert_true(confirmed.close())
}

///|
test "native report reservation is bounded and does not block cleanup or ACK" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    fail("real SQLite library is required")
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    fail("real SQLite root is required")
  }
  let library = @sqlite.load_library(path).unwrap()
  let journal = open_journal(
    library,
    root + "/reports-full-" + @env.now().to_string() + ".sqlite3",
    2097152L,
    test_control(test_site()),
  ).unwrap()
  let request = test_request("report-bound")
  journal.accept(request).unwrap() |> ignore
  let original = report_fixture(request, "original")
  journal.retain_output_report(original).unwrap()
  for index in 0..<31 {
    let custody = report_fixture(request, "occurrence-" + index.to_string())
    journal
    .reserve_output_report(@remote.remote_output_report_custody_output(custody))
    .unwrap()
  }
  let extra = report_fixture(request, "extra")
  assert_true(
    journal.reserve_output_report(
      @remote.remote_output_report_custody_output(extra),
    )
    is Err(Physical(@sqlite.CapacityExceeded)),
  )
  journal.retain_output_report(original).unwrap()
  journal.retain_output_intent("cleanup-full", "exact").unwrap()
  journal.complete_output_intent("cleanup-full").unwrap()
  let ack = @remote.remote_output_report_reply_json(
    @remote.remote_output_report_custody_result(original),
    @remote.RemoteOutputReportReply::Accepted,
  ).unwrap()
  journal
  .record_output_report_reply(
    @remote.remote_output_report_custody_key(original),
    ack,
  )
  .unwrap()
  assert_eq(journal.pending_output_intents().unwrap().length(), 0)
  assert_true(journal.close())
}
