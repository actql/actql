///|
// Physical Native definitions only until a separately selected execution lane.
// Only a fixture-owned Store custody binding is installed; no Result is committed.
fn local_publisher_fixture(
  name : String,
  publish : Bool,
) -> (
  NativeLocalHostConnection,
  @host.ClientRequestIdentity,
  @publication.PublicationContract,
  @publication_store.Store,
) {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let entries = [
    (
      #|{"entry_id":"submit","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["submit"]},"exclusions":[]}
    ),
  ]
  if publish {
    entries.push(
      (
        #|{"entry_id":"publish","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["publish"]},"exclusions":[]}
      ),
    )
  }
  let account = @utf8.encode(
    "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[" +
    entries.join(",") +
    "]}",
  )
  let writer = root.create_writer(name + ".account.stage", 4096L).unwrap()
  writer.append(account).unwrap()
  writer.seal(name + ".account.json").unwrap() |> ignore
  let writer = root.create_writer(name + ".run.stage", 4096L).unwrap()
  writer
  .append(
    @utf8.encode(
      "{\"version\":\"actql-config/0.1\",\"native\":{\"run\":{\"namespace_id\":\"local\",\"store_authority_cid\":\"sha256:" +
      "b".repeat(64) +
      "\"}}}",
    ),
  )
  .unwrap()
  writer.seal(name + ".run.json").unwrap() |> ignore
  let crypto = epoch_test_crypto()
  let host = begin_native_local_host_adoption(
      path,
      name + ".host",
      path,
      name + ".account.json",
      "operator",
      crypto,
      configuration_files=[name + ".run.json"],
    )
    .unwrap()
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    name,
    name + "-run",
    scope~,
  )
  host.journal
  .bind_run(
    request,
    prepared,
    compiled,
    definition,
    host.authorize({
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "submit",
    })
    is Ok(Allow(_)),
  )
  .unwrap()
  |> ignore
  root.create_directory(name + ".store").unwrap() |> ignore
  let store = @publication_store.open_store(
    local_journal_test_library(),
    path + "/" + name + ".store",
    "sha256:" + "b".repeat(64),
    256L,
    8L,
    65536L,
  ).unwrap()
  let publication = install_native_client_cancellation_publication(
    store, "local", 65536, 8192, 64,
  ).unwrap()
  host.journal
  .bind_installed_publication(request, publication, () => {
    host.authorize({
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "submit",
    })
    is Ok(Allow(_))
  })
  .unwrap()
  (host, request, definition, store)
}

///|
fn local_publisher_context(
  binding : NativeLocalPublisherBinding,
) -> @publication.PublicationRequestContext {
  let result = @publication.result_definition_contract(
    @publication.prepare_result_definition(
      @host.client_request_program_cid(binding.request),
      "answer",
    ).unwrap(),
  )
  let request = @publication.issue_publication_request(
    binding.definition,
    [result],
    "local",
    binding.authority.scope,
    binding.publication_policy_cid(),
    "sha256:" + "b".repeat(64),
    "2026-10-12T00:00:00.000Z",
    65536,
    8192,
    64,
  ).unwrap()
  @publication.project_publication_request_context(request).unwrap()
}

///|
fn local_publisher_facts(
  context : @publication.PublicationRequestContext,
) -> @native_publication.NativeRunPublicationAuthorization {
  {
    stage: "request",
    namespace_id: context.namespace_id,
    authority_scope_cid: context.authority_scope_cid,
    run_definition_cid: context.run_definition_cid,
    publication_request_cid: context.publication_request_cid,
    public_index_entry_cid: None,
  }
}

///|
test "Native Local publisher rejects submit-only Account without publication" {
  let (host, request, definition, store) = local_publisher_fixture(
    "publisher-submit-only", false,
  )
  assert_true(
    host.bind_run_publisher(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      definition,
      "publisher-submit-only.run.json",
      store,
    )
    is Err(Journal(AuthorizationDenied)),
  )
  host.close().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "Native Local publisher binds original Account selected Store and Run without revision changes" {
  let (host, request, definition, store) = local_publisher_fixture(
    "publisher-originals", true,
  )
  let binding = host
    .bind_run_publisher(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      definition,
      "publisher-originals.run.json",
      store,
    )
    .unwrap()
  let before = host.journal.lookup(request, binding.current()).unwrap()
  let context = local_publisher_context(binding)
  let facts = local_publisher_facts(context)
  assert_true(binding.authorize_request(context, facts))
  assert_eq(binding.account_body, host.session.source_body)
  assert_eq(
    binding.publication_policy_cid(),
    host.configuration().unwrap().configuration_cid(),
  )
  for
    changed in [
      { ..context, namespace_id: "foreign", },
      { ..context, authority_scope_cid: "sha256:" + "f".repeat(64), },
      { ..context, run_definition_cid: "sha256:" + "f".repeat(64), },
      { ..context, publication_policy_cid: "sha256:" + "f".repeat(64), },
      { ..context, publication_target_cid: "sha256:" + "f".repeat(64), },
    ] {
    assert_false(
      binding.authorize_request(changed, local_publisher_facts(changed)),
    )
  }
  assert_false(
    binding.authorize_request(context, {
      ..facts,
      publication_request_cid: "sha256:" + "f".repeat(64),
    }),
  )
  let after = host.journal.lookup(request, binding.current()).unwrap()
  guard before is Retained(before) && after is Retained(after) else {
    abort("expected retained original")
  }
  assert_eq(before.revision, after.revision)
  host.close().unwrap()
  assert_true(store.close().unwrap())
  assert_false(binding.current())
  assert_false(binding.authorize_request(context, facts))
}

///|
test "Native Local publisher refuses foreign caller missing selection and foreign Run" {
  let (host, request, definition, store) = local_publisher_fixture(
    "publisher-foreign", true,
  )
  assert_true(
    host.bind_run_publisher(
      epoch_test_crypto(),
      "other",
      "cli",
      request,
      definition,
      "publisher-foreign.run.json",
      store,
    )
    is Err(Journal(AuthorizationDenied)),
  )
  assert_true(
    host.bind_run_publisher(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      definition,
      "unselected.json",
      store,
    )
    is Err(SelectionMismatch),
  )
  let (_, _, _, foreign) = journal_test_run("foreign", "foreign-run")
  assert_true(
    host.bind_run_publisher(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      foreign,
      "publisher-foreign.run.json",
      store,
    )
    is Err(SelectionMismatch),
  )
  host.close().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "Native Local publisher keeps lost configuration custody unavailable instead of repairing" {
  let (host, request, definition, store) = local_publisher_fixture(
    "publisher-lost-custody", true,
  )
  let binding = host
    .bind_run_publisher(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      definition,
      "publisher-lost-custody.run.json",
      store,
    )
    .unwrap()
  let context = local_publisher_context(binding)
  let facts = local_publisher_facts(context)
  assert_true(binding.authorize_request(context, facts))
  let table = @utf8.encode("client_local_adoption")
  let key = @utf8.encode("adoption")
  assert_true(
    submitted_test_remove_record(
      host.database,
      table,
      table.length(),
      key,
      key.length(),
    ),
  )
  assert_false(binding.current())
  assert_false(binding.authorize_request(context, facts))
  assert_true(
    host.database.read("client_local_adoption", "adoption")
    is Err(@sqlite.NotFound),
  )
  host.close().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "Native Local publisher rejects a foreign Store even with the same authority CID" {
  let (host, request, definition, store) = local_publisher_fixture(
    "publisher-store", true,
  )
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  root.create_directory("publisher-other-store").unwrap() |> ignore
  let foreign = @publication_store.open_store(
    local_journal_test_library(),
    path + "/publisher-other-store",
    "sha256:" + "b".repeat(64),
    256L,
    8L,
    65536L,
  ).unwrap()
  assert_true(
    host.bind_run_publisher(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      definition,
      "publisher-store.run.json",
      foreign,
    )
    is Err(SelectionMismatch),
  )
  assert_true(foreign.close().unwrap())
  host.close().unwrap()
  assert_true(store.close().unwrap())
}
