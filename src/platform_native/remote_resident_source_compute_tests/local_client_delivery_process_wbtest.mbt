///|
/// Physical Native writer/readers over the original Run. The writer uses the
/// actual Source fixture; readers never prepare, compile or execute a Program.
/// This is an Owner/API handoff, not public Local CLI ingress acceptance.
test "Native actual Source delivery survives exited writer and original Submission readers" {
  let phase = @env.get_env_var("ACTQL_TEST_NATIVE_SOURCE_DELIVERY_PHASE")
  assert_true(phase is None || phase == Some("write") || phase == Some("read"))
  if phase != Some("read") {
    local_client_source_publication_case(false, delivery_handoff=true)
  }
  if phase != Some("write") {
    native_source_delivery_reader()
  }
}

///|
fn native_source_delivery_reader() -> Unit raise {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT").unwrap()
  let name = "native-client-source-delivery-process.duckdb"
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let database = sqlite
    .open_database(root + "/" + name + ".sqlite3", 131072L)
    .unwrap()
  let saved = (key : String) => {
    @utf8.decode(
      database.read("test_source_delivery_reference", key).unwrap().body,
    )
  }
  let reference = @client.admit_native_client_submission_reference(
    saved("submission"),
  ).unwrap()
  let scope = saved("scope")
  let original_run = saved("run")
  let journal = @client.open_native_client_run_journal(database, 8).unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let authority = @client.open_native_client_epoch_authority(
    database, crypto, 100.0,
  ).unwrap()
  guard journal.lookup_submitted_intent(
      authority, reference, scope, true, 1200.0,
    )
    is Ok(@client.Submitted(original)) &&
    @client.native_client_submitted_run_admission(original) is Some(admission) else {
    fail("original Submission lost its accepted Run")
  }
  assert_eq(
    @client.native_client_submitted_run_definition_cid(admission),
    saved("run"),
  )
  let request = @client.native_client_submitted_run_request(admission)
  guard journal.lookup(request, true) is Ok(@client.Retained(before)) else {
    fail("original Run missing")
  }
  let before_revision = @client.native_client_run_record_revision(before)
  let store_path = root + "/" + name + "-publication"
  let store = @store.open_store(
    sqlite,
    store_path,
    local_client_publication_cid("native-client-original-store"),
    128L,
    8L,
    1000000L,
  ).unwrap()
  let read_calls = Ref(0)
  let allowed = Ref(true)
  let metadata = @access.install_native_result_access_authority(
    _ => {
      read_calls.val += 1
      false
    },
    _ => {
      read_calls.val += 1
      None
    },
    _ => {
      read_calls.val += 1
      false
    },
    authorize_lookup=Some(requested => {
      allowed.val && requested.principal_id == "fixture-principal"
    }),
  )
  let service = @access.install_native_result_access_service(
    store,
    metadata,
    () => {
      read_calls.val += 1
      "2099-01-01T00:00:00.000Z"
    },
    1000000,
    100000,
    16,
    128,
    3,
  ).unwrap()
  let selection : @client.NativeClientDeliveryAttemptSelection = {
    namespace_id: "native-client-fixture",
    principal_id: "fixture-principal",
    purpose: "inspect",
    result_name: "answer",
    attempt_id: "native-cli-sink-after-reopen",
  }
  let lost_attempt = store
    .read_publication_contract("delivery_attempt", saved("lost_attempt"))
    .unwrap()
  let lost_grant = @publication.delivery_attempt_read_grant_cid(lost_attempt).unwrap()
  let audit = sqlite
    .open_database(store_path + "/.actql-publication.sqlite3", 1000000L)
    .unwrap()
  let lost_usage_before = audit
    .read("result_read_grant_usage", lost_grant)
    .unwrap()
  for _ in 0..<2 {
    guard journal.lookup_submitted_result_delivery(
        authority,
        reference,
        scope,
        () => true,
        1200.0,
        service,
        { ..selection, attempt_id: "native-cli-open-response-lost", },
      )
      is Ok(Some(lost)) &&
      lost.record is Some(record) else {
      fail("lost opening was not reconciled to its original attempt")
    }
    assert_eq(
      @publication.publication_contract_identity(lost.attempt),
      saved("lost_attempt"),
    )
    assert_eq(
      @publication.publication_contract_identity(record),
      saved("lost_record"),
    )
    let projection = @publication.project_delivery_record(record).unwrap()
    assert_eq(projection.state, "streaming")
    assert_eq(projection.confirmed_byte_count, 0L)
    assert_true(lost.host_release_receipt is None)
  }
  for _ in 0..<2 {
    guard journal.lookup_submitted_result_delivery(
        authority,
        reference,
        scope,
        () => true,
        1200.0,
        service,
        selection,
      )
      is Ok(Some(value)) &&
      value.record is Some(record) &&
      value.host_release_receipt is Some(receipt) else {
      fail("original completed delivery was not restored")
    }
    assert_eq(
      @publication.publication_contract_identity(value.attempt),
      saved("attempt"),
    )
    assert_eq(
      @publication.publication_contract_identity(record),
      saved("record"),
    )
    assert_eq(
      @publication.publication_contract_identity(receipt),
      saved("receipt"),
    )
    let projection = @publication.project_delivery_record(record).unwrap()
    assert_eq(projection.state, "succeeded")
    assert_eq(projection.confirmed_byte_count, 9L)
  }
  allowed.val = false
  assert_true(
    journal.lookup_submitted_result_delivery(
      authority,
      reference,
      scope,
      () => true,
      1200.0,
      service,
      selection,
    )
    is Err(@client.ResultAccess(@access.AccessDenied)),
  )
  allowed.val = true
  assert_true(
    journal.lookup_submitted_result_delivery(
      authority,
      reference,
      scope,
      () => true,
      1200.0,
      service,
      { ..selection, attempt_id: "absent-original-attempt", },
    )
    is Ok(None),
  )
  assert_eq(read_calls.val, 0)
  // Explicit reread creates a new read/grant, never a new Submission/Run.
  let new_attempt = @env.get_env_var(
    "ACTQL_TEST_NATIVE_SOURCE_DELIVERY_READ_ID",
  ).unwrap_or("same-process-reread")
  let admissions = Ref(0)
  let read_authority = @access.install_native_result_access_authority(
    requested => {
      requested.run_definition_cid == original_run &&
      requested.principal_id == "fixture-principal"
    },
    _ => {
      admissions.val += 1
      Some({
        authorization_context_cid: local_client_publication_cid(
          new_attempt + "-auth",
        ),
        data_ceiling_cid: local_client_publication_cid(new_attempt + "-ceiling"),
        egress_admission_cid: local_client_publication_cid(
          new_attempt + "-egress",
        ),
        expires_at: "2099-01-01T00:00:00.000Z",
        max_bytes: 128,
        max_uses: 1,
      })
    },
    _ => true,
  )
  let read_service = @access.install_native_result_access_service(
    store,
    read_authority,
    () => "2026-10-10T00:00:09.000Z",
    1000000,
    100000,
    16,
    128,
    3,
  ).unwrap()
  let session = journal
    .open_submitted_result(
      authority,
      reference,
      scope,
      () => true,
      1200.0,
      read_service,
      {
        namespace_id: selection.namespace_id,
        principal_id: selection.principal_id,
        purpose: selection.purpose,
        result_name: selection.result_name,
        format: "jsonl",
        attempt_id: new_attempt,
      },
    )
    .unwrap()
  assert_true(session.attempt_cid() != saved("attempt"))
  let output : Array[Byte] = []
  let sink = @access.install_native_result_sink(
    session,
    3,
    9,
    bytes => {
      for byte in bytes {
        output.push(byte)
      }
      @access.SinkChunkConfirmed
    },
    () => true,
  ).unwrap()
  let mut completed = false
  for _ in 0..<40 {
    match sink.poll().unwrap() {
      @access.SinkComplete(receipt) => {
        assert_eq(receipt.confirmed_bytes, 9L)
        completed = true
        break
      }
      @access.SinkProgress => ()
      _ => fail("explicit reread failed")
    }
  }
  assert_true(completed)
  assert_eq(@utf8.decode(Bytes::from_array(output)), "{\"id\":3}\n")
  assert_eq(admissions.val, 1)
  sink.close().unwrap()
  assert_eq(
    store.inspect_result_delivery(selection.attempt_id).unwrap().delivery_record_cid,
    saved("record"),
  )
  guard journal.lookup(request, true) is Ok(@client.Retained(after)) else {
    fail("original Run disappeared")
  }
  assert_eq(@client.native_client_run_record_revision(after), before_revision)
  assert_eq(saved("acquisitions"), "1")
  assert_eq(saved("consumers"), "1")
  assert_eq(saved("cleanups"), "1")
  let lost_usage_after = audit
    .read("result_read_grant_usage", lost_grant)
    .unwrap()
  assert_eq(lost_usage_after.body, lost_usage_before.body)
  assert_eq(lost_usage_after.revision, lost_usage_before.revision)
  assert_eq(
    store.inspect_result_delivery("native-cli-open-response-lost").unwrap().delivery_record_cid,
    saved("lost_record"),
  )
  audit.close_checked().unwrap()
  assert_true(store.close().unwrap())
  database.close_checked().unwrap()
}
