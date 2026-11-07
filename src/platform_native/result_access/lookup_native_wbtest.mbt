///|
test "Native authorized metadata lookup preserves original attempt without reopening or read admission" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_root(root).unwrap()
  let name = "lookup-" + @env.now().to_string()
  parent.create_directory(name).unwrap() |> ignore
  let path = root + "/" + name
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let store_authority = native_access_cid(name + "-store")
  let store = @store.open_store(
    library, path, store_authority, 256L, 8L, 65536L,
  ).unwrap()
  let fixture = native_access_fixture(store, store_authority, name)
  commit_access_fixture(store, fixture)
  let admissions = Ref(0)
  let reads = Ref(0)
  let clocks = Ref(0)
  let allowed = Ref(true)
  let authorization = install_native_result_access_authority(
    _ => true,
    _ => {
      admissions.val += 1
      Some({
        authorization_context_cid: native_access_cid(name + "-auth"),
        data_ceiling_cid: native_access_cid(name + "-ceiling"),
        egress_admission_cid: native_access_cid(name + "-egress"),
        expires_at: "2026-09-21T00:00:00.000Z",
        max_bytes: 64,
        max_uses: 1,
      })
    },
    _ => {
      reads.val += 1
      true
    },
    authorize_lookup=Some(_ => allowed.val),
  )
  let service = install_native_result_access_service(
    store,
    authorization,
    () => {
      clocks.val += 1
      "2026-09-20T01:00:00.000Z"
    },
    65536,
    4096,
    32,
    65536,
    3,
  ).unwrap()
  let scope : @publication.DeliveryAttemptLookupScope = {
    namespace_id: "namespace_id",
    authority_scope_cid: fixture.authority_scope_cid,
    run_definition_cid: @publication.publication_contract_identity(
      fixture.run_definition,
    ),
    principal_id: "principal",
    purpose: "download",
    result_name: "answer",
    attempt_id: "original-opening",
  }
  let session = open_native_result_access(service, {
    namespace_id: scope.namespace_id,
    authority_scope_cid: scope.authority_scope_cid,
    run_definition_cid: scope.run_definition_cid,
    principal_id: scope.principal_id,
    purpose: scope.purpose,
    result_name: scope.result_name,
    attempt_id: scope.attempt_id,
    format: "jsonl",
  }).unwrap()
  let attempt_cid = session.attempt_cid()
  // No byte reaches the caller. Closing this physical session is not a new
  // delivery, a success receipt, Run cancellation or permission to retry it.
  session.close().unwrap()
  assert_true(store.close().unwrap())
  let reopened = @store.open_store(
    library, path, store_authority, 256L, 8L, 65536L,
  ).unwrap()
  let audit = library
    .open_database(path + "/.actql-publication.sqlite3", 65536L)
    .unwrap()
  let attempt = reopened
    .read_publication_contract("delivery_attempt", attempt_cid)
    .unwrap()
  let grant_cid = @publication.delivery_attempt_read_grant_cid(attempt).unwrap()
  let usage_before = audit.read("result_read_grant_usage", grant_cid).unwrap()
  let head_before = audit.read("delivery_record_head", attempt_cid).unwrap()
  let historical = install_native_result_access_service(
    reopened,
    authorization,
    () => {
      clocks.val += 1
      "2099-01-01T00:00:00.000Z"
    },
    65536,
    4096,
    32,
    65536,
    3,
  ).unwrap()
  let clock_before = clocks.val
  let read_before = reads.val
  guard lookup_native_result_delivery_attempt(historical, scope)
    is Ok(Some(original)) else {
    fail("saved original attempt lost")
  }
  assert_eq(
    @publication.publication_contract_identity(original.attempt),
    attempt_cid,
  )
  guard original.record is Some(record) else {
    fail("saved streaming record lost")
  }
  assert_eq(
    @publication.project_delivery_record(record).unwrap().state,
    "streaming",
  )
  assert_true(original.host_release_receipt is None)
  for
    changed in [
      { ..scope, namespace_id: "foreign", },
      { ..scope, authority_scope_cid: native_access_cid("foreign"), },
      { ..scope, run_definition_cid: native_access_cid("foreign"), },
      { ..scope, principal_id: "foreign", },
      { ..scope, purpose: "foreign", },
      { ..scope, result_name: "foreign", },
      { ..scope, attempt_id: "absent", },
    ] {
    assert_true(
      lookup_native_result_delivery_attempt(historical, changed) is Ok(None),
    )
  }
  allowed.val = false
  assert_true(
    lookup_native_result_delivery_attempt(historical, scope)
    is Err(AccessDenied),
  )
  assert_true(
    lookup_native_result_delivery_attempt(historical, {
      ..scope,
      attempt_id: "absent",
    })
    is Err(AccessDenied),
  )
  allowed.val = true
  let policy_calls = Ref(0)
  let late = install_native_result_access_authority(
    _ => true,
    _ => None,
    _ => true,
    authorize_lookup=Some(_ => {
      policy_calls.val += 1
      policy_calls.val == 1
    }),
  )
  let late_service = install_native_result_access_service(
    reopened,
    late,
    () => "2099-01-01T00:00:00.000Z",
    65536,
    4096,
    32,
    65536,
    3,
  ).unwrap()
  assert_true(
    lookup_native_result_delivery_attempt(late_service, scope)
    is Err(AccessDenied),
  )
  assert_true(
    lookup_native_result_delivery_attempt(historical, scope) is Ok(Some(_)),
  )
  assert_eq(admissions.val, 1)
  assert_eq(reads.val, read_before)
  assert_eq(clocks.val, clock_before)
  let usage_after = audit.read("result_read_grant_usage", grant_cid).unwrap()
  let head_after = audit.read("delivery_record_head", attempt_cid).unwrap()
  assert_eq(usage_after.body, usage_before.body)
  assert_eq(usage_after.revision, usage_before.revision)
  assert_eq(head_after.body, head_before.body)
  assert_eq(head_after.revision, head_before.revision)
  audit.close_checked().unwrap()
  assert_true(reopened.close().unwrap())
}

///|
test "Native lookup without a separately installed hook never borrows read permission" {
  let (store, session, _) = sink_access_case("lookup-unavailable")
  session.close().unwrap()
  let calls = Ref(0)
  let authority = install_native_result_access_authority(
    _ => {
      calls.val += 1
      true
    },
    _ => {
      calls.val += 1
      None
    },
    _ => {
      calls.val += 1
      true
    },
  )
  let service = install_native_result_access_service(
    store,
    authority,
    () => {
      calls.val += 1
      "2026-09-20T01:00:00.000Z"
    },
    65536,
    4096,
    32,
    65536,
    3,
  ).unwrap()
  assert_true(
    lookup_native_result_delivery_attempt(service, {
      namespace_id: "namespace_id",
      authority_scope_cid: native_access_cid("scope"),
      run_definition_cid: native_access_cid("run"),
      principal_id: "principal",
      purpose: "download",
      result_name: "answer",
      attempt_id: "absent",
    })
    is Err(LookupUnavailable),
  )
  assert_eq(calls.val, 0)
  assert_true(store.close().unwrap())
}
