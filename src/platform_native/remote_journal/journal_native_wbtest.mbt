///|
fn test_cid(fill : String) -> String {
  "sha256:" + fill
}

///|
#borrow(library, path, key, body)
extern "C" fn test_unclosed_coordinator(
  library : @sqlite.Library,
  path : Bytes,
  path_length : Int,
  key : Bytes,
  key_length : Int,
  body : Bytes,
  body_length : Int,
  missing_schema : Bool,
) -> Bool = "actql_native_sqlite_test_unclosed_coordinator"

///|
#borrow(path)
extern "C" fn test_file_bytes(path : Bytes, length : Int) -> Bytes = "actql_native_sqlite_test_file_bytes"

///|
#borrow(database)
extern "C" fn test_fail_inspection_close(
  database : @sqlite.Database,
  failures : Int,
) -> Unit = "actql_native_sqlite_test_fail_close"

///|
#borrow(database)
extern "C" fn test_checked_close_count(database : @sqlite.Database) -> Int = "actql_native_sqlite_test_checked_close_count"

///|
fn test_source_bytes(path : String) -> Array[Bytes] {
  ["", "-wal", "-shm", "-journal"].map(suffix => {
    let bytes = @utf8.encode(path + suffix)
    test_file_bytes(bytes, bytes.length())
  })
}

///|
fn test_historyless_body(request : @remote.DispatchRequest) -> Bytes {
  let admission = @remote.prepare_coordinator_dispatch_intent(
    @remote.create_coordinator_dispatch_journal("native-coordinator").unwrap(),
    request,
  ).unwrap()
  @utf8.encode(
    @remote.coordinator_dispatch_admission_durable_json(admission)
    .unwrap()
    .replace(
      old="actql-remote-coordinator-history-record/0.1",
      new="actql-remote-coordinator-record/0.1",
    )
    .replace(old="\"observation_history_json\":\"[]\",", new=""),
  )
}

///|
test "native Coordinator refuses old and unknown WAL formats before source writes" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(library_path).unwrap()
  for missing_schema in [false, true] {
    let request = test_request("format-refusal")
    let key = @utf8.encode(
      @remote.dispatch_request_attempt_identity(request).unwrap(),
    )
    let body = test_historyless_body(request)
    let path = root +
      "/coordinator-format-" +
      @env.now().to_string() +
      "-" +
      missing_schema.to_string() +
      ".sqlite3"
    let encoded = @utf8.encode(path)
    assert_true(
      test_unclosed_coordinator(
        library,
        encoded,
        encoded.length(),
        key,
        key.length(),
        body,
        body.length(),
        missing_schema,
      ),
    )
    let before = test_source_bytes(path)
    assert_true(before[0].length() > 0)
    assert_true(before[1].length() > 0)
    assert_eq(before[2].length(), 0)
    let refused = open_coordinator_journal(
      library,
      path,
      1048576L,
      @remote.create_coordinator_dispatch_journal("native-coordinator").unwrap(),
    )
    if missing_schema {
      assert_true(refused is Err(Physical(@sqlite.DatabaseOpen(_))))
    } else {
      assert_true(refused is Err(Protocol(@remote.ObservationHistoryRequired)))
    }
    assert_eq(test_source_bytes(path), before)
  }
}

///|
test "native Coordinator inspection retains primary and retry-only physical cleanup" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(library_path).unwrap()
  let request = test_request("inspection-cleanup")
  let key = @utf8.encode(
    @remote.dispatch_request_attempt_identity(request).unwrap(),
  )
  let body = test_historyless_body(request)
  let path = root +
    "/coordinator-inspection-cleanup-" +
    @env.now().to_string() +
    ".sqlite3"
  let encoded = @utf8.encode(path)
  assert_true(
    test_unclosed_coordinator(
      library,
      encoded,
      encoded.length(),
      key,
      key.length(),
      body,
      body.length(),
      false,
    ),
  )
  let before = test_source_bytes(path)
  let cleanup : CoordinatorInitializationCleanup = {
    inspection: inspection_open(encoded, encoded.length()),
    database: None,
    pending: true,
  }
  let primary = inspect_coordinator_copy(
    library,
    1048576L,
    cleanup,
    @remote.create_coordinator_dispatch_journal("native-coordinator").unwrap(),
  )
  assert_true(primary is Err(Protocol(@remote.ObservationHistoryRequired)))
  let database = cleanup.database.unwrap()
  test_fail_inspection_close(database, 1)
  guard finish_coordinator_inspection(cleanup, primary)
    is Err(
      InitializationCleanupPending(
        Some(Protocol(@remote.ObservationHistoryRequired)),
        Physical(@sqlite.Physical(_)),
        retained
      )
    ) else {
    fail("inspection lost its primary failure or cleanup owner")
  }
  assert_true(retained.pending())
  assert_eq(test_checked_close_count(database), 1)
  retained.retry().unwrap()
  assert_false(retained.pending())
  assert_true(retained.database is None)
  assert_eq(test_checked_close_count(database), 2)
  retained.retry().unwrap()
  assert_eq(test_checked_close_count(database), 2)
  assert_eq(test_source_bytes(path), before)
}

///|
fn test_site() -> @site.ExecutionSite {
  @site.create_site(
    "native-site",
    4,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
}

///|
fn test_control(site : @site.ExecutionSite) -> @remote.SiteDispatchJournal {
  @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap()
}

///|
fn test_request(dispatch_id : String) -> @remote.DispatchRequest {
  test_request_for(
    dispatch_id,
    7,
    4,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
}

///|
fn test_request_for(
  dispatch_id : String,
  task_attempt : Int,
  site_generation : Int,
  runtime_revision : String,
) -> @remote.DispatchRequest {
  @remote.prepare_dispatch_request(
    "native-coordinator",
    test_cid("0000000000000000000000000000000000000000000000000000000000000000"),
    "task-a",
    task_attempt,
    dispatch_id,
    "native-site",
    site_generation,
    runtime_revision,
    "local",
    "local/1",
    "strategy/1",
    test_cid("1111111111111111111111111111111111111111111111111111111111111111"),
    test_cid("2222222222222222222222222222222222222222222222222222222222222222"),
    test_cid("3333333333333333333333333333333333333333333333333333333333333333"),
    test_cid("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
    test_cid("4444444444444444444444444444444444444444444444444444444444444444"),
  ).unwrap()
}

///|
fn test_capability(
  site : @site.ExecutionSite,
) -> @remote.RemoteExecutionCapability {
  @remote.register_remote_execution_capability(
    site,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    "local",
    "local/1",
    "strategy/1",
    test_cid("4444444444444444444444444444444444444444444444444444444444444444"),
  ).unwrap()
}

///|
fn test_managed_output(
  request : @remote.DispatchRequest,
) -> (
  @remote.RemoteExecutionEvidence,
  @remote.RemoteManagedOutputSubject,
  @remote.RemoteManagedOutputMeasurement,
) {
  let site = test_site()
  let journal = test_control(site)
  let (_, record) = @remote.commit_dispatch_acceptance(
    @remote.prepare_dispatch_acceptance(journal, request).unwrap(),
    true,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_begin_provisioning(record, test_capability(site)).unwrap(),
    true,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_begin_remote_execution(record).unwrap(),
    true,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_confirm_native_settled(record).unwrap(),
    true,
  ).unwrap()
  let holding = @remote.remote_output_holding_evidence_cid(
    request, "native-material", 1L,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_retain_remote_output(record, "native-material", holding).unwrap(),
    true,
  ).unwrap()
  let measurement = @remote.prepare_remote_managed_output_measurement(
    1,
    1,
    1,
    1,
    [1],
    [1],
    [1],
    [1],
    [0],
    [1],
  ).unwrap()
  let subject = @remote.prepare_remote_managed_output_subject(
    @remote.dispatch_request_identity(request),
    "native-material",
    holding,
    test_cid("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
    test_cid("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
    test_cid("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
    test_cid("1111111111111111111111111111111111111111111111111111111111111111"),
    test_cid("2222222222222222222222222222222222222222222222222222222222222222"),
    @remote.remote_managed_output_measurement_cid(measurement),
    1,
    1L,
  ).unwrap()
  let issuer = @remote.register_remote_evidence_issuer(
    site,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_managed_output_evidence_kind(),
    test_cid("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
  ).unwrap()
  (
    @remote.issue_remote_managed_output_evidence(issuer, record, subject).unwrap(),
    subject,
    measurement,
  )
}

///|
test "native remote journal durably accepts reconciles and fences transitions" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root + "/remote-" + @env.now().to_string() + ".sqlite3"
  let first_site = test_site()
  let second_site = test_site()
  let first = open_journal(
    library,
    database_path,
    262144L,
    test_control(first_site),
  ).unwrap()
  let second = open_journal(
    library,
    database_path,
    262144L,
    test_control(second_site),
  ).unwrap()
  let request = test_request("dispatch-a")
  let (first_kind, first_record) = first.accept(request).unwrap()
  assert_eq(first_kind, @remote.NewDispatch)
  let (second_kind, second_record) = second.accept(request).unwrap()
  assert_eq(second_kind, @remote.ExistingDispatch)
  assert_true(second.accept(test_request("dispatch-b")) is Err(StateCollision))
  let first_provision = @remote.prepare_begin_provisioning(
    first_record,
    test_capability(first_site),
  ).unwrap()
  let second_provision = @remote.prepare_begin_provisioning(
    second_record,
    test_capability(second_site),
  ).unwrap()
  first.commit_transition(first_provision).unwrap()
  second.commit_transition(second_provision).unwrap()
  let running = @remote.prepare_begin_remote_execution(first_record).unwrap()
  let failed = @remote.prepare_confirm_execution_failed(second_record).unwrap()
  first.commit_transition(running).unwrap()
  assert_true(second.commit_transition(failed) is Err(StateCollision))
  assert_true(first.close())
  assert_true(second.close())
  let reopened_site = test_site()
  let reopened = open_journal(
    library,
    database_path,
    262144L,
    test_control(reopened_site),
  ).unwrap()
  let recovered = reopened.recover_after("").unwrap().unwrap()
  assert_eq(
    recovered.0,
    @remote.dispatch_request_attempt_identity(request).unwrap(),
  )
  assert_eq(@remote.dispatch_record_revision(recovered.1), 2)
  assert_true(reopened.recover_after(recovered.0).unwrap() is None)
  let (reopened_kind, reopened_record) = reopened.accept(request).unwrap()
  assert_eq(reopened_kind, @remote.ExistingDispatch)
  assert_eq(@remote.dispatch_record_revision(reopened_record), 2)
  assert_eq(@remote.dispatch_record_state_codes(reopened_record)[0], 2)
  assert_true(reopened.close())
  assert_false(reopened.close())
}

///|
test "native Site journal atomically restores typed output evidence" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/remote-observation-" +
    @env.now().to_string() +
    ".sqlite3"
  let site = test_site()
  let journal = open_journal(
    library,
    database_path,
    1048576L,
    test_control(site),
  ).unwrap()
  let request = test_request("dispatch-observation")
  let (_, record) = journal.accept(request).unwrap()
  journal
  .commit_transition(
    @remote.prepare_begin_provisioning(record, test_capability(site)).unwrap(),
  )
  .unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  journal
  .commit_transition(@remote.prepare_confirm_native_settled(record).unwrap())
  .unwrap()
  journal
  .commit_transition(
    @remote.prepare_retain_remote_output(
      record,
      "native-material",
      @remote.remote_output_holding_evidence_cid(request, "native-material", 1L).unwrap(),
    ).unwrap(),
  )
  .unwrap()
  let (evidence, subject, measurement) = test_managed_output(request)
  let transition = @remote.prepare_durable_execution_evidence(record, evidence).unwrap()
  guard journal.commit_transition(transition)
    is Err(Protocol(@remote.InvalidTransition)) else {
    fail("CID-only evidence transition was accepted")
  }
  journal
  .commit_evidence_transition(transition, evidence, subject, measurement)
  .unwrap()
  assert_true(journal.close())

  let reopened = open_journal(
    library,
    database_path,
    1048576L,
    test_control(test_site()),
  ).unwrap()
  let restored = reopened.observation(request).unwrap()
  guard recovered_site_dispatch_evidence(restored) is Some(restored_evidence) else {
    fail("durable execution evidence was not restored")
  }
  guard recovered_site_dispatch_subject(restored) is Some(restored_subject) else {
    fail("durable output subject was not restored")
  }
  guard recovered_site_dispatch_measurement(restored)
    is Some(restored_measurement) else {
    fail("durable output measurement was not restored")
  }
  assert_eq(
    @remote.remote_execution_evidence_cid(restored_evidence),
    @remote.remote_execution_evidence_cid(evidence),
  )
  assert_eq(
    @remote.remote_managed_output_subject_cid(restored_subject),
    @remote.remote_managed_output_subject_cid(subject),
  )
  assert_eq(
    @remote.remote_managed_output_measurement_cid(restored_measurement),
    @remote.remote_managed_output_measurement_cid(measurement),
  )
  let status_body = @remote.remote_dispatch_status_json(
    recovered_site_dispatch_record(restored),
    Some(restored_evidence),
    Some(restored_subject),
    Some(restored_measurement),
  ).unwrap()
  let status = @remote.admit_remote_dispatch_response_json(
    status_body,
    request,
    @remote.StatusReply,
  ).unwrap()
  assert_true(@remote.remote_dispatch_response_evidence(status) is Some(_))
  assert_true(reopened.close())
}

///|
test "native Site recovery rejects evidence without its typed observation" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/remote-incomplete-observation-" +
    @env.now().to_string() +
    ".sqlite3"
  let site = test_site()
  let journal = open_journal(
    library,
    database_path,
    1048576L,
    test_control(site),
  ).unwrap()
  let request = test_request("dispatch-incomplete-observation")
  let (_, record) = journal.accept(request).unwrap()
  journal
  .commit_transition(
    @remote.prepare_begin_provisioning(record, test_capability(site)).unwrap(),
  )
  .unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  journal
  .commit_transition(@remote.prepare_confirm_native_settled(record).unwrap())
  .unwrap()
  journal
  .commit_transition(
    @remote.prepare_retain_remote_output(
      record,
      "native-material",
      @remote.remote_output_holding_evidence_cid(request, "native-material", 1L).unwrap(),
    ).unwrap(),
  )
  .unwrap()
  let (evidence, _, _) = test_managed_output(request)
  let transition = @remote.prepare_durable_execution_evidence(record, evidence).unwrap()
  let key = @remote.dispatch_request_attempt_identity(request).unwrap()
  let physical = library.open_database(database_path, 1048576L).unwrap()
  ignore(
    physical
    .compare_exchange(
      "site_dispatch",
      key,
      @remote.dispatch_transition_expected_revision(transition).to_int64(),
      @utf8.encode(
        @remote.dispatch_transition_durable_json(transition).unwrap(),
      ),
    )
    .unwrap(),
  )
  physical.close()
  assert_true(journal.observation(request) is Err(_))
  assert_true(journal.recover_after("") is Err(_))
  assert_true(journal.close())
}

///|
test "native Site restart durably fences the old generation" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/remote-restart-" +
    @env.now().to_string() +
    ".sqlite3"
  let old_site = test_site()
  let journal = open_journal(
    library,
    database_path,
    262144L,
    test_control(old_site),
  ).unwrap()
  let request = test_request("dispatch-restart")
  let (_, record) = journal.accept(request).unwrap()
  let stale = open_journal(
    library,
    database_path,
    262144L,
    test_control(test_site()),
  ).unwrap()
  let stale_record = stale.require(request).unwrap()
  let stale_progress = @remote.prepare_begin_provisioning(
    stale_record,
    test_capability(test_site()),
  ).unwrap()
  journal
  .commit_transition(
    @remote.prepare_begin_provisioning(record, test_capability(old_site)).unwrap(),
  )
  .unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  let next_revision = test_cid(
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  )
  let replacement = @site.create_site(
    "native-site", 5, next_revision, 4, 4, 1048576L, 1048576L,
  ).unwrap()
  assert_eq(journal.restart(replacement).unwrap(), 1)
  assert_eq(@remote.dispatch_record_state_codes(record), [6, 0, 3, 0, 0])
  assert_true(
    stale.accept(
      test_request_for(
        "stale-new",
        8,
        4,
        test_cid(
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        ),
      ),
    )
    is Err(StaleSiteBinding),
  )
  assert_true(stale.commit_transition(stale_progress) is Err(StaleSiteBinding))
  assert_true(stale.require(request) is Ok(_))
  assert_true(stale.close())
  assert_true(journal.close())

  guard open_journal(library, database_path, 262144L, test_control(test_site()))
    is Err(StateCollision) else {
    fail("the old Site generation reopened after restart")
  }
  let reopened_site = @site.create_site(
    "native-site", 5, next_revision, 4, 4, 1048576L, 1048576L,
  ).unwrap()
  let reopened = open_journal(
    library,
    database_path,
    262144L,
    test_control(reopened_site),
  ).unwrap()
  let recovered = reopened.recover_after("").unwrap().unwrap()
  assert_eq(@remote.dispatch_record_state_codes(recovered.1), [6, 0, 3, 0, 0])
  guard reopened.accept(request) is Err(Protocol(@remote.StaleSiteGeneration)) else {
    fail("the old dispatch authority was revived")
  }
  assert_true(
    @remote.prepare_begin_remote_release(recovered.1)
    is Err(@remote.InvalidTransition),
  )
  // This journal fixture explicitly supplies a confirmed physical stop.
  // Restart alone never supplies that fact or permits release.
  let stopped = @remote.prepare_remote_runtime_cleanup(
    recovered.1,
    false,
    true,
    false,
  ).unwrap()
  assert_eq(@remote.remote_runtime_step_action_code(stopped), 2)
  reopened
  .commit_transition(@remote.remote_runtime_step_transition(stopped).unwrap())
  .unwrap()
  reopened
  .commit_transition(@remote.prepare_begin_remote_release(recovered.1).unwrap())
  .unwrap()
  reopened
  .commit_transition(
    @remote.prepare_confirm_remote_release(recovered.1).unwrap(),
  )
  .unwrap()
  assert_eq(@remote.dispatch_record_state_codes(recovered.1), [4, 0, 2, 0, 0])
  let (new_kind, _) = reopened
    .accept(test_request_for("new-generation", 8, 5, next_revision))
    .unwrap()
  assert_eq(new_kind, @remote.NewDispatch)
  assert_true(reopened.close())
}

///|
test "native force loss durably quarantines exact responsibility" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/remote-force-loss-" +
    @env.now().to_string() +
    ".sqlite3"
  let site = test_site()
  let journal = open_journal(
    library,
    database_path,
    262144L,
    test_control(site),
  ).unwrap()
  let request = test_request("dispatch-force-loss")
  let (_, record) = journal.accept(request).unwrap()
  assert_true(
    journal.force_loss(record, false)
    is Err(Protocol(@remote.UnauthorizedForceLoss)),
  )
  journal.force_loss(record, true).unwrap()
  assert_eq(@remote.dispatch_record_state_codes(record), [6, 0, 4, 0, 1])
  assert_true(journal.close())

  let reopened = open_journal(
    library,
    database_path,
    262144L,
    test_control(test_site()),
  ).unwrap()
  let recovered = reopened.require(request).unwrap()
  assert_eq(@remote.dispatch_record_state_codes(recovered), [6, 0, 4, 0, 1])
  reopened
  .commit_transition(
    @remote.prepare_reconcile_cleanup_after_loss(recovered).unwrap(),
  )
  .unwrap()
  assert_eq(@remote.dispatch_record_state_codes(recovered), [6, 0, 5, 0, 0])
  assert_true(reopened.close())
}

///|
test "native remote recovery rejects a durable key alias" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/remote-alias-" +
    @env.now().to_string() +
    ".sqlite3"
  let site = test_site()
  let journal = open_journal(
    library,
    database_path,
    262144L,
    test_control(site),
  ).unwrap()
  let request = test_request("dispatch-alias")
  let (_, record) = journal.accept(request).unwrap()
  let body = @utf8.encode(@remote.dispatch_record_durable_json(record).unwrap())
  let physical = library.open_database(database_path, 262144L).unwrap()
  ignore(physical.insert("site_dispatch", "alias", body).unwrap())
  physical.close()
  guard journal.recover_after("") is Err(StateCollision) else {
    fail("durable record under a foreign key was restored")
  }
  assert_true(journal.close())
}

///|
test "native Coordinator journal restores intent and uncertainty" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/coordinator-" +
    @env.now().to_string() +
    ".sqlite3"
  let first = open_coordinator_journal(
    library,
    database_path,
    1048576L,
    @remote.create_coordinator_dispatch_journal("native-coordinator").unwrap(),
  ).unwrap()
  let request = test_request("coordinator-dispatch")
  let (kind, record) = first.accept(request).unwrap()
  assert_eq(kind, @remote.NewDispatch)
  assert_true(
    first.accept(test_request("competing-dispatch")) is Err(StateCollision),
  )
  first
  .commit_transition(
    @remote.prepare_coordinator_outcome_unknown(record).unwrap(),
  )
  .unwrap()
  assert_true(first.close())
  let reopened = open_coordinator_journal(
    library,
    database_path,
    1048576L,
    @remote.create_coordinator_dispatch_journal("native-coordinator").unwrap(),
  ).unwrap()
  let recovered = reopened.recover_after("").unwrap().unwrap()
  let recovered_record = recovered_coordinator_dispatch_record(recovered)
  assert_eq(@remote.coordinator_dispatch_record_revision(recovered_record), 1)
  assert_eq(
    @remote.coordinator_dispatch_record_state_codes(recovered_record)[1],
    "1",
  )
  assert_true(recovered_coordinator_dispatch_evidence(recovered) is None)
  assert_true(
    reopened
    .recover_after(recovered_coordinator_dispatch_key(recovered))
    .unwrap()
    is None,
  )
  let (retry_kind, retry_record) = reopened.accept(request).unwrap()
  assert_eq(retry_kind, @remote.ExistingDispatch)
  assert_eq(@remote.coordinator_dispatch_record_revision(retry_record), 1)
  assert_true(reopened.close())
}

///|
test "native Coordinator journal retains exact observation receipts without revising replay" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/coordinator-replay-" +
    @env.now().to_string() +
    ".sqlite3"
  let coordinator = open_coordinator_journal(
    library,
    database_path,
    1048576L,
    @remote.create_coordinator_dispatch_journal("native-coordinator").unwrap(),
  ).unwrap()
  let request = test_request("coordinator-replay")
  let (_, record) = coordinator.accept(request).unwrap()
  for revision in [1, 3] {
    coordinator
    .commit_transition(
      @remote.prepare_coordinator_site_observation(
        record,
        revision,
        2,
        0,
        0,
        false,
        false,
        None,
      ).unwrap(),
    )
    .unwrap()
  }
  let key = @remote.dispatch_request_attempt_identity(request).unwrap()
  let before = coordinator.database.read("coordinator_dispatch", key).unwrap()
  assert_eq(before.revision, 2L)
  assert_true(coordinator.close())
  let reopened = open_coordinator_journal(
    library,
    database_path,
    1048576L,
    @remote.create_coordinator_dispatch_journal("native-coordinator").unwrap(),
  ).unwrap()
  let restored = recovered_coordinator_dispatch_record(
    reopened.recover_after("").unwrap().unwrap(),
  )
  for revision in [3, 1] {
    let replay = @remote.prepare_coordinator_site_observation(
      restored,
      revision,
      2,
      0,
      0,
      false,
      false,
      None,
    ).unwrap()
    assert_true(@remote.coordinator_dispatch_transition_is_replay(replay))
    reopened.commit_transition(replay).unwrap()
    let after = reopened.database.read("coordinator_dispatch", key).unwrap()
    assert_eq(after.revision, before.revision)
    assert_eq(after.body, before.body)
    assert_eq(@remote.coordinator_dispatch_record_revision(restored), 2)
    assert_false(
      @remote.coordinator_exact_retransmission_eligible(restored, request),
    )
  }
  assert_true(
    @remote.prepare_coordinator_site_observation(
      restored,
      2,
      2,
      0,
      0,
      false,
      false,
      None,
    )
    is Err(@remote.StateCollision),
  )
  assert_true(
    @remote.prepare_coordinator_site_observation(
      restored,
      1,
      4,
      0,
      0,
      false,
      false,
      None,
    )
    is Err(@remote.StateCollision),
  )
  assert_true(reopened.close())
}

///|
test "native Coordinator journal restores typed completion evidence" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/coordinator-evidence-" +
    @env.now().to_string() +
    ".sqlite3"
  let coordinator = open_coordinator_journal(
    library,
    database_path,
    1048576L,
    @remote.create_coordinator_dispatch_journal("native-coordinator").unwrap(),
  ).unwrap()
  let request = test_request("coordinator-evidence")
  let (_, record) = coordinator.accept(request).unwrap()
  let (evidence, subject, measurement) = test_managed_output(request)
  let transition = @remote.prepare_coordinator_managed_output_observation(
    record, 5, 3, 2, 0, true, false, evidence, subject, measurement,
  ).unwrap()
  coordinator
  .commit_transition(
    transition,
    evidence=Some(evidence),
    subject=Some(subject),
    measurement=Some(measurement),
  )
  .unwrap()
  assert_true(coordinator.close())
  let reopened = open_coordinator_journal(
    library,
    database_path,
    1048576L,
    @remote.create_coordinator_dispatch_journal("native-coordinator").unwrap(),
  ).unwrap()
  let recovered = reopened.recover_after("").unwrap().unwrap()
  assert_true(
    @remote.coordinator_completion_evidence_available(
      recovered_coordinator_dispatch_record(recovered),
    ),
  )
  assert_true(recovered_coordinator_dispatch_evidence(recovered) is Some(_))
  assert_true(recovered_coordinator_dispatch_subject(recovered) is Some(_))
  assert_true(recovered_coordinator_dispatch_measurement(recovered) is Some(_))
  assert_true(reopened.close())
}

///|
test "native start claim lets exactly one executor begin an attempt" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/remote-start-claim-" +
    @env.now().to_string() +
    ".sqlite3"
  let first_site = test_site()
  let second_site = test_site()
  let first = open_journal(
    library,
    database_path,
    262144L,
    test_control(first_site),
  ).unwrap()
  let second = open_journal(
    library,
    database_path,
    262144L,
    test_control(second_site),
  ).unwrap()
  let request = test_request("dispatch-claim")
  let (_, first_record) = first.accept(request).unwrap()
  let (_, second_record) = second.accept(request).unwrap()
  let first_start = @remote.prepare_begin_provisioning(
    first_record,
    test_capability(first_site),
  ).unwrap()
  let second_start = @remote.prepare_begin_provisioning(
    second_record,
    test_capability(second_site),
  ).unwrap()
  // Both transitions have identical bodies; only the claim decides.
  assert_eq(first.start_claimant(request).unwrap(), None)
  assert_eq(first.claim_start(first_start, "executor-a").unwrap(), Won)
  assert_eq(first.start_claimant(request).unwrap(), Some("executor-a"))
  assert_eq(second.start_claimant(request).unwrap(), Some("executor-a"))
  assert_eq(
    second.claim_start(second_start, "executor-b").unwrap(),
    LostTo("executor-a"),
  )
  // A retry by the winner, as after a lost reply, is recognised.
  assert_eq(
    second.claim_start(second_start, "executor-a").unwrap(),
    AlreadyMine,
  )
  assert_eq(@remote.dispatch_record_state_codes(first_record)[0], 1)
  // Only the start transition can be claimed, by a well-formed claimant.
  assert_true(
    first.claim_start(
      @remote.prepare_begin_remote_execution(first_record).unwrap(),
      "executor-a",
    )
    is Err(Protocol(@remote.InvalidTransition)),
  )
  let other = test_request_for(
    "dispatch-claim-invalid",
    9,
    4,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  let (_, other_record) = first.accept(other).unwrap()
  assert_true(
    first.claim_start(
      @remote.prepare_begin_provisioning(
        other_record,
        test_capability(first_site),
      ).unwrap(),
      "executor a",
    )
    is Err(Protocol(@remote.InvalidTransition)),
  )
  assert_true(first.close())
  assert_true(second.close())
}

///|
test "native claimant recovery rejects corrupt or foreign durable claims" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/claimant-recovery-" +
    @env.now().to_string() +
    ".sqlite3"
  let site = test_site()
  let journal = open_journal(
    library,
    database_path,
    262144L,
    test_control(site),
  ).unwrap()
  let request = test_request("claimant-recovery")
  let (_, record) = journal.accept(request).unwrap()
  assert_eq(journal.start_claimant(request).unwrap(), None)
  journal
  .claim_start(
    @remote.prepare_begin_provisioning(record, test_capability(site)).unwrap(),
    "holder-original",
  )
  .unwrap()
  |> ignore
  assert_true(journal.close())
  assert_true(journal.start_claimant(request) is Err(Closed))
  let reopened = open_journal(
    library,
    database_path,
    262144L,
    test_control(test_site()),
  ).unwrap()
  assert_eq(reopened.start_claimant(request).unwrap(), Some("holder-original"))
  let key = @remote.dispatch_request_attempt_identity(request).unwrap()
  for
    body in [
      "{",
      start_claim_body(
        "holder-original",
        @remote.dispatch_request_identity(test_request("foreign")),
      ),
      start_claim_body(
        "invalid claimant",
        @remote.dispatch_request_identity(request),
      ),
    ] {
    let saved = reopened.database.read("site_start_claim", key).unwrap()
    reopened.database
    .compare_exchange(
      "site_start_claim",
      key,
      saved.revision,
      @utf8.encode(body),
    )
    .unwrap()
    |> ignore
    assert_true(reopened.start_claimant(request) is Err(StateCollision))
  }
  assert_true(reopened.close())
}

///|
test "native start claim and cancellation race on the Accepted state" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/remote-start-cancel-" +
    @env.now().to_string() +
    ".sqlite3"
  let site = test_site()
  let journal = open_journal(
    library,
    database_path,
    262144L,
    test_control(site),
  ).unwrap()
  let canceller_site = test_site()
  let canceller = open_journal(
    library,
    database_path,
    262144L,
    test_control(canceller_site),
  ).unwrap()
  // Cancellation first: the claim loses and nothing starts.
  let cancelled_request = test_request("dispatch-cancel-first")
  let (_, record) = journal.accept(cancelled_request).unwrap()
  let (_, cancel_record) = canceller.accept(cancelled_request).unwrap()
  let resender = open_journal(
    library,
    database_path,
    262144L,
    test_control(test_site()),
  ).unwrap()
  let (_, resend_record) = resender.accept(cancelled_request).unwrap()
  let cancel = @remote.prepare_confirm_execution_cancelled(cancel_record).unwrap()
  let resent = @remote.prepare_confirm_execution_cancelled(resend_record).unwrap()
  canceller.commit_transition(cancel).unwrap()
  // The same cancellation sent again is idempotent.
  resender.commit_transition(resent).unwrap()
  assert_true(resender.close())
  assert_eq(
    journal
    .claim_start(
      @remote.prepare_begin_provisioning(record, test_capability(site)).unwrap(),
      "executor-a",
    )
    .unwrap(),
    Cancelled,
  )
  // Claim first: a later cancellation of Accepted cannot apply.
  let started_request = test_request_for(
    "dispatch-claim-first",
    8,
    4,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  let (_, started) = journal.accept(started_request).unwrap()
  let (_, late) = canceller.accept(started_request).unwrap()
  assert_eq(
    journal
    .claim_start(
      @remote.prepare_begin_provisioning(started, test_capability(site)).unwrap(),
      "executor-a",
    )
    .unwrap(),
    Won,
  )
  assert_true(
    canceller.commit_transition(
      @remote.prepare_confirm_execution_cancelled(late).unwrap(),
    )
    is Err(StateCollision),
  )
  assert_true(journal.close())
  assert_true(canceller.close())
}

///|
test "native journal keeps one exact dispatch envelope per attempt" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/remote-envelope-" +
    @env.now().to_string() +
    ".sqlite3"
  let journal = open_journal(
    library,
    database_path,
    262144L,
    test_control(test_site()),
  ).unwrap()
  let request = test_request("dispatch-envelope")
  let key = @remote.dispatch_request_attempt_identity(request).unwrap()
  assert_eq(journal.dispatch_envelope(key).unwrap(), None)
  journal.retain_dispatch_envelope(request, "{\"envelope\":1}").unwrap()
  journal.retain_dispatch_envelope(request, "{\"envelope\":1}").unwrap()
  assert_true(
    journal.retain_dispatch_envelope(request, "{\"envelope\":2}")
    is Err(StateCollision),
  )
  let reader = open_journal(
    library,
    database_path,
    262144L,
    test_control(test_site()),
  ).unwrap()
  assert_eq(reader.dispatch_envelope(key).unwrap(), Some("{\"envelope\":1}"))
  // An envelope past the journal's record bound is refused; nothing is kept.
  let other = test_request_for(
    "dispatch-envelope-large",
    8,
    4,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  assert_true(
    journal.retain_dispatch_envelope(other, "x".repeat(262145))
    is Err(Physical(@sqlite.BodyTooLarge)),
  )
  assert_eq(
    journal
    .dispatch_envelope(
      @remote.dispatch_request_attempt_identity(other).unwrap(),
    )
    .unwrap(),
    None,
  )
  assert_true(journal.close())
  assert_true(reader.close())
}

///|
test "native journal keeps output intents until their cleanup is complete" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/remote-output-intent-" +
    @env.now().to_string() +
    ".sqlite3"
  let journal = open_journal(
    library,
    database_path,
    262144L,
    test_control(test_site()),
  ).unwrap()
  assert_eq(journal.pending_output_intents().unwrap().length(), 0)
  journal.retain_output_intent("sha256:a", "{\"intent\":\"a\"}").unwrap()
  // A retry after a lost reply is idempotent; other bytes are refused.
  journal.retain_output_intent("sha256:a", "{\"intent\":\"a\"}").unwrap()
  assert_true(
    journal.retain_output_intent("sha256:a", "{\"intent\":\"x\"}")
    is Err(StateCollision),
  )
  journal.retain_output_intent("sha256:b", "{\"intent\":\"b\"}").unwrap()
  // Another process sees both, in key order.
  let reader = open_journal(
    library,
    database_path,
    262144L,
    test_control(test_site()),
  ).unwrap()
  assert_eq(reader.pending_output_intents().unwrap(), [
    ("sha256:a", "{\"intent\":\"a\"}"),
    ("sha256:b", "{\"intent\":\"b\"}"),
  ])
  // Completion is recorded once, repeats are idempotent, and only an
  // existing intent can be completed.
  reader.complete_output_intent("sha256:a").unwrap()
  reader.complete_output_intent("sha256:a").unwrap()
  assert_true(reader.complete_output_intent("sha256:c") is Err(MissingDispatch))
  assert_eq(journal.pending_output_intents().unwrap(), [
    ("sha256:b", "{\"intent\":\"b\"}"),
  ])
  // A completed intent is never reopened.
  assert_true(
    journal.retain_output_intent("sha256:a", "{\"intent\":\"a\"}")
    is Err(StateCollision),
  )
  assert_true(journal.close())
  assert_true(reader.close())
}
