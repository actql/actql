///|
test "Native material retains typed rows only from the original admitted session" {
  let root_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_root(root_path).unwrap()
  let name = "material-typed-" + @env.now().to_string()
  parent.create_directory(name).unwrap() |> ignore
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let authority = native_access_cid(name + "-store")
  let store = @store.open_store(
    library,
    root_path + "/" + name,
    authority,
    256L,
    8L,
    65536L,
  ).unwrap()
  let fixture = native_access_fixture(
    store,
    authority,
    name,
    checked_schema=Some("{\"value\":{\"nullable\":false,\"type\":\"number\"}}"),
  )
  commit_access_fixture(store, fixture)
  let request : NativeResultAccessRequest = {
    namespace_id: "namespace_id",
    authority_scope_cid: fixture.authority_scope_cid,
    run_definition_cid: @publication.publication_contract_identity(
      fixture.run_definition,
    ),
    principal_id: "principal",
    purpose: "cli-table",
    result_name: "answer",
    format: "json",
    attempt_id: name + "-one-attempt",
  }
  let receiver = prepare_native_result_material_receiver(
    store,
    request,
    native_access_cid(name + "-receiver"),
    64,
    1,
    64,
    1,
    3,
    4096,
    32,
    [native_access_cid(name + "-data-policy")],
  ).unwrap()
  assert_true(receiver.table(256) is Err(MaterialNotComplete))
  assert_false(receiver.matches_request({ ..request, attempt_id: "foreign", }))
  let stages : Array[String] = []
  let policy = install_native_result_access_authority(
    _ => true,
    _ => {
      Some({
        authorization_context_cid: native_access_cid(name + "-auth"),
        data_ceiling_cid: native_access_cid(name + "-ceiling"),
        egress_admission_cid: native_access_cid(name + "-egress"),
        expires_at: "2026-09-21T00:00:00.000Z",
        max_bytes: 64,
        max_uses: 1,
      })
    },
    facts => {
      stages.push(facts.stage)
      facts.stage != "table_output"
    },
  )
  let service = install_native_result_access_service(
    store,
    policy,
    () => "2026-09-20T01:00:00.000Z",
    65536,
    4096,
    32,
    64,
    3,
  ).unwrap()
  let session = open_native_result_access(service, request).unwrap()
  assert_true(session.matches_original(store, request))
  for
    foreign in [
      { ..request, namespace_id: "foreign", },
      { ..request, authority_scope_cid: native_access_cid("foreign"), },
      { ..request, run_definition_cid: native_access_cid("foreign"), },
      { ..request, principal_id: "foreign", },
      { ..request, purpose: "foreign", },
      { ..request, result_name: "foreign", },
      { ..request, format: "jsonl", },
      { ..request, attempt_id: "foreign", },
    ] {
    assert_false(session.matches_original(store, foreign))
  }
  receiver.attach(session).unwrap()
  assert_true(receiver.attach(session) is Err(MaterialForeignSession))
  let mut complete = false
  for _ in 0..<64 {
    if receiver.poll().unwrap() {
      complete = true
      break
    }
  }
  assert_true(complete)
  assert_false(session.matches_original(store, request))
  assert_eq(receiver.table(256).unwrap(), "value\n-----\n7\n")
  assert_true(stages.contains("receipt"))
  assert_true(session.next(1) is Err(InvalidProgress))
  // A material receipt cannot stand in for the independent output decision.
  assert_true(receiver.write_table(256) is Err(MaterialAccess(AccessDenied)))
  assert_true(receiver.write_table(256) is Err(MaterialOutputAlreadyAttempted))
  assert_eq(stages.filter(stage => stage == "table_output").length(), 1)
  receiver.close().unwrap()
  assert_true(receiver.table(256) is Err(MaterialClosed))
  receiver.close().unwrap()
  assert_true(store.close().unwrap())
  parent.close().unwrap()
}
