///|
// Native physical cases are defined independently of CLI output. These use
// the installed declarative Account Owner, never a caller-supplied callback.
let policy_account_original : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"explicit-policy-operations\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"result/answer\",\"run\"]},\"operation\":{\"any_of\":[\"read\",\"submit\"]},\"exclusions\":[]}]}"

///|
fn policy_host_fixture(
  name : String,
  existing? : Bool = false,
  files? : Array[String] = [],
  account_body? : Bytes = policy_account_original,
  legacy_evidence? : Bool = false,
  state_parent? : String? = None,
) -> NativeLocalHostConnection {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent_path = match state_parent {
    Some(selected) => selected
    None => path
  }
  let account = name + ".account.json"
  if !existing {
    let parent = @filesystem.open_private_root(path).unwrap()
    let writer = parent.create_writer(name + ".stage", 4096L).unwrap()
    writer.append(account_body).unwrap()
    writer.seal(account).unwrap() |> ignore
  }
  let session = begin_native_local_host_adoption(
    parent_path,
    name + ".host",
    path,
    account,
    "operator",
    epoch_test_crypto(),
    existing_only=existing,
    configuration_files=files,
  ).unwrap()
  if !legacy_evidence {
    return session
      .open_journal(
        local_journal_test_library(),
        epoch_test_crypto(),
        100.0,
        8,
        8388608L,
      )
      .unwrap()
  }
  // Construct a new prior-format installation through the original bootstrap
  // transaction, omitting only the later evidence index. No old state is used.
  if existing {
    abort("legacy fixture requires a fresh installation")
  }
  let crypto = epoch_test_crypto()
  let (ownership, adoption) = session.prepare_journal_file(crypto).unwrap()
  if !session.prepare_journal_marker(ownership, adoption).unwrap() {
    abort("fresh legacy marker lost")
  }
  let database = local_journal_test_library()
    .initialize_owned_database(
      session.state_path + "/client.sqlite3",
      ownership,
      131072L,
    )
    .unwrap()
  let calls : Array[String] = []
  let bootstrap = journal_test_bootstrap_access(database, calls)
  let legacy : NativeClientJournalBootstrapAccess = {
    ..bootstrap,
    install_read_evidence_schema: _ => Ok(()),
  }
  initialize_native_local_client_custody(
    database,
    crypto,
    adoption,
    settings=Some(session.settings),
    bootstrap=Some(legacy),
  ).unwrap()
  if database.client_read_evidence_schema().unwrap() != 0 {
    abort("legacy index unexpectedly installed")
  }
  session
  .bind_journal(
    database,
    crypto,
    ownership,
    adoption,
    false,
    100.0,
    8,
    [],
    None,
    None,
  )
  .unwrap()
}

///|
// These source-free Programs have no contributing Source policy. Admit the
// independently authored Result policy through the same checked Host entrance
// as the publication-routing fixture, before binding the original Run.
fn policy_test_result_original(
  unselected : @host.ClientCompiledRun,
) -> (@host.ClientCompiledRun, String) {
  let cid = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let body = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  let compiled = @host.with_client_source_free_result_policy(
    unselected, cid, body, 65536, 8192, 64,
  ).unwrap()
  let original = @host.client_compiled_run_source_free_result_policy_body(
    compiled,
  ).unwrap()
  (compiled, @publication.captured_effect_dependency_body_cid(original))
}

///|
test "Native original publication Policy packet survives journal reopen without work" {
  let name = "run-policy-original-reopen"
  let host = policy_host_fixture(name)
  let crypto = epoch_test_crypto()
  let journal = host.run_journal().unwrap()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, unselected, definition) = journal_test_run(
    "policy-request",
    "policy-run",
    scope~,
  )
  let (compiled, root) = policy_test_result_original(unselected)
  let bound = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  let old_body = run_record_body(bound).unwrap()
  assert_false(
    (@utf8.decode(old_body) catch { _ => fail("invalid original row") }).contains(
      "publication_policy_originals",
    ),
  )
  assert_eq(
    run_record_body(read_run_record({ body: old_body, revision: 0L, }).unwrap()).unwrap(),
    old_body,
  )
  assert_true(
    host.lookup_publication_policy_original(
      crypto, "operator", "cli", request, "answer", root,
    )
    is Err(PublicationPolicy(@checked.MissingDependency)),
  )
  let stored = host
    .retain_publication_policy_originals(
      crypto, "operator", "cli", request, prepared, compiled, definition,
    )
    .unwrap()
  assert_eq(stored.revision, 1L)
  assert_false(stored.dispatch_reserved)
  assert_false(stored.physical_start_claimed)
  let original = stored.publication_policy_originals.unwrap()
  let first = host
    .lookup_publication_policy_original(
      crypto, "operator", "cli", request, "answer", root,
    )
    .unwrap()
  assert_eq(
    host
    .retain_publication_policy_originals(
      crypto, "operator", "cli", request, prepared, compiled, definition,
    )
    .unwrap().revision,
    1L,
  )
  host.close().unwrap()
  let reopened = policy_host_fixture(name, existing=true)
  let journal = reopened.run_journal().unwrap()
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("original Run missing")
  }
  assert_eq(record.publication_policy_originals, Some(original))
  assert_false(record.dispatch_reserved)
  assert_false(record.physical_start_claimed)
  let restored = reopened
    .lookup_publication_policy_original(
      crypto, "operator", "cli", request, "answer", root,
    )
    .unwrap()
  assert_eq(
    @publication.captured_effect_dependency_body_json(restored),
    @publication.captured_effect_dependency_body_json(first),
  )
  assert_true(
    reopened.lookup_publication_policy_original(
      crypto,
      "operator",
      "cli",
      request,
      "answer",
      "sha256:" + "f".repeat(64),
    )
    is Err(PublicationPolicy(@checked.MissingDependency)),
  )
  reopened.close().unwrap()
}

///|
test "Native Policy original custody refuses foreign Host scope and current generation replacement" {
  let name = "run-policy-authority"
  let host = policy_host_fixture(name)
  // Adoption locks belong to the state parent, independently of state names.
  // Keep both actual Hosts open with their own original exclusive locks.
  let state_parent = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/run-policy-foreign-parent"
  host.session.source_root
  .create_directory("run-policy-foreign-parent")
  .unwrap()
  |> ignore
  let foreign = policy_host_fixture(
    "run-policy-another-host",
    state_parent=Some(state_parent),
  )
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, unselected, definition) = journal_test_run(
    "policy-request",
    "policy-run",
    scope~,
  )
  let (compiled, root) = policy_test_result_original(unselected)
  let journal = host.run_journal().unwrap()
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  assert_true(
    foreign.retain_publication_policy_originals(
      crypto, "operator", "cli", request, prepared, compiled, definition,
    )
    is Err(AuthorizationDenied),
  )
  assert_true(
    host.retain_publication_policy_originals(
      crypto, "another-operator", "cli", request, prepared, compiled, definition,
    )
    is Err(AuthorizationDenied),
  )
  host
  .retain_publication_policy_originals(
    crypto, "operator", "cli", request, prepared, compiled, definition,
  )
  .unwrap()
  |> ignore
  assert_true(
    host.lookup_publication_policy_original(
      crypto, "operator", "cli", request, "unpermitted-result", root,
    )
    is Err(AuthorizationDenied),
  )
  assert_true(
    foreign.lookup_publication_policy_original(
      crypto, "operator", "cli", request, "answer", root,
    )
    is Err(AuthorizationDenied),
  )
  let parent = host.session.source_root
  let account = name + ".account.json"
  let generation = parent.inspect_generation(account).unwrap().unwrap()
  parent.reclaim_generation(account, generation).unwrap()
  let writer = parent
    .create_writer("run-policy-replacement.stage", 4096L)
    .unwrap()
  writer.append(policy_account_original).unwrap()
  writer.seal(account).unwrap() |> ignore
  assert_true(
    host.lookup_publication_policy_original(
      crypto, "operator", "cli", request, "answer", root,
    )
    is Err(AuthorizationDenied),
  )
  assert_true(
    host.retain_publication_policy_originals(
      crypto, "operator", "cli", request, prepared, compiled, definition,
    )
    is Err(AuthorizationDenied),
  )
  host.close().unwrap()
  foreign.close().unwrap()
}

///|
test "Native Policy original custody never repairs a started Run and refuses malformed originals" {
  let host = policy_host_fixture("run-policy-started")
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let journal = host.run_journal().unwrap()
  let (request, prepared, unselected, definition) = journal_test_run(
    "policy-request",
    "policy-run",
    scope~,
  )
  let (compiled, root) = policy_test_result_original(unselected)
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let (_, _, _, another) = journal_test_run(
    "policy-request",
    "another-run",
    scope~,
  )
  assert_true(
    host.retain_publication_policy_originals(
      crypto, "operator", "cli", request, prepared, compiled, another,
    )
    is Err(ForeignRun),
  )
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  assert_true(journal.claim_physical_start(request, true).unwrap())
  assert_true(
    host.retain_publication_policy_originals(
      crypto, "operator", "cli", request, prepared, compiled, definition,
    )
    is Err(Fenced),
  )
  assert_true(
    host.lookup_publication_policy_original(
      crypto, "operator", "cli", request, "answer", root,
    )
    is Err(PublicationPolicy(@checked.MissingDependency)),
  )
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("started original Run missing")
  }
  assert_eq(record.publication_policy_originals, None)
  for
    invalid in [
      "null",
      "{}",
      "{\"bodies\":[],\"root_policy_cid\":\"sha256:" + "a".repeat(64) + "\"}",
    ] {
    assert_true(read_run_policy_originals(invalid) is Err(CustodyLost))
  }
  let bad = { ..record, publication_policy_originals: Some("{}"), }
  assert_true(
    read_run_record({
      body: run_record_body(bad).unwrap(),
      revision: record.revision,
    })
    is Err(CustodyLost),
  )
  host.close().unwrap()
}
