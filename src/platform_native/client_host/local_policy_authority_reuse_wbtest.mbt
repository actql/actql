///|
// Independent canonical and malformed fixtures keep their own exact selectors.
// Account wire selectors use UTF-16 order, distinct from Core String comparison.
let policy_reuse_account_original : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"explicit-policy-operations\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"result/answer\",\"run\"]},\"operation\":{\"any_of\":[\"read\",\"submit\"]},\"exclusions\":[]}]}"

///|
let policy_reuse_unsorted_account_original : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"explicit-policy-operations\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\",\"result/answer\"]},\"operation\":{\"any_of\":[\"read\",\"submit\"]},\"exclusions\":[]}]}"

///|
// Concurrent Hosts retain independent adoption locks in separate private parents.
// The original shared fixture remains unchanged, including its typed refusal.
fn policy_reuse_host_fixture(name : String) -> NativeLocalHostConnection {
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(base).unwrap()
  parent.create_directory(name + ".parent").unwrap() |> ignore
  let path = base + "/" + name + ".parent"
  let root = @filesystem.open_private_root(path).unwrap()
  let writer = root.create_writer("account.stage", 4096L).unwrap()
  writer.append(policy_reuse_account_original).unwrap()
  writer.seal("account.json").unwrap() |> ignore
  begin_native_local_host_adoption(
    path,
    "host",
    path,
    "account.json",
    "operator",
    epoch_test_crypto(),
  )
  .unwrap()
  .open_journal(
    local_journal_test_library(),
    epoch_test_crypto(),
    100.0,
    8,
    8388608L,
  )
  .unwrap()
}

///|
// Definitions only until a matching Native fixture is allocated and executed.
test "Native policy material is fresh per predicate and unavailable after original Host close" {
  // Keep the explicit unsorted-selector refusal independent of other fixture
  // repairs; this does not weaken admission to reach the actual current path.
  assert_eq(
    @authorization.admit_account_configuration_json(
      @utf8.decode(policy_reuse_unsorted_account_original),
    ).map(_ => ()),
    Err(@authorization.NonCanonicalOrder("$.entries[0].resource.any_of[1]")),
  )
  let host = policy_reuse_host_fixture("local-policy-reuse-closed")
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, _, _, _) = journal_test_run("reuse", "reuse-run", scope~)
  let authority = native_local_policy_authority_for(
    host,
    crypto,
    "operator",
    "cli",
    request,
    ReadResultPolicy("answer"),
  ).unwrap()
  assert_true(authority.current_for(host.journal, request))
  host.close().unwrap()
  assert_false(authority.current_for(host.journal, request))
}

///|
test "Native policy material cannot share another journal or authorize a different Result" {
  let host = policy_reuse_host_fixture("local-policy-reuse-original")
  let other = policy_reuse_host_fixture("local-policy-reuse-foreign")
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, _, _, _) = journal_test_run(
    "reuse-scope",
    "reuse-scope-run",
    scope~,
  )
  let authority = native_local_policy_authority_for(
    host,
    crypto,
    "operator",
    "cli",
    request,
    ReadResultPolicy("answer"),
  ).unwrap()
  assert_false(authority.current_for(other.journal, request))
  assert_true(
    native_local_policy_authority_for(
      host,
      crypto,
      "operator",
      "cli",
      request,
      ReadResultPolicy("other"),
    )
    is Err(AuthorizationDenied),
  )
  other.close().unwrap()
  host.close().unwrap()
}

///|
test "Native signing RunRead stays fresh and cannot substitute a named Result role" {
  let host = policy_reuse_host_fixture("local-policy-signing-read")
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, _, _, _) = journal_test_run(
    "signing-read",
    "signing-read-run",
    scope~,
  )
  let authority = native_local_policy_authority_for(
    host,
    crypto,
    "operator",
    "cli",
    request,
    ReadRunMaterials,
    fresh_account=true,
  ).unwrap()
  assert_true(authority.current_signing_for(host.journal, request))
  let named = native_local_policy_authority_for(
    host,
    crypto,
    "operator",
    "cli",
    request,
    ReadResultPolicy("answer"),
  ).unwrap()
  assert_true(named.current_for(host.journal, request))
  assert_false(named.current_signing_for(host.journal, request))
  assert_true(
    native_local_policy_authority_for(
      host,
      crypto,
      "foreign",
      "cli",
      request,
      ReadRunMaterials,
      fresh_account=true,
    )
    is Err(AuthorizationDenied),
  )
  host.close().unwrap()
  assert_false(authority.current_signing_for(host.journal, request))
}
