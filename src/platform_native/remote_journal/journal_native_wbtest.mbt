///|
fn test_cid(fill : String) -> String {
  "sha256:" + fill
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
  @remote.prepare_dispatch_request(
    "native-coordinator",
    test_cid("0000000000000000000000000000000000000000000000000000000000000000"),
    "task-a",
    7,
    dispatch_id,
    "native-site",
    4,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
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
  @remote.commit_dispatch_transition(
    @remote.prepare_retain_remote_output(
      record,
      "native-material",
      test_cid(
        "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      ),
    ).unwrap(),
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
    test_cid("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
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
