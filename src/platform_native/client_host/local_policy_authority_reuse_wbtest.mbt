///|
// Independently canonical fixture; the original failing shared fixture is retained.
// Account wire selectors use UTF-16 order, distinct from Core String comparison.
let policy_reuse_account_original : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"explicit-policy-operations\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"result/answer\",\"run\"]},\"operation\":{\"any_of\":[\"read\",\"submit\"]},\"exclusions\":[]}]}"

///|
// Definitions only until a matching Native fixture is allocated and executed.
test "Native policy material is fresh per predicate and unavailable after original Host close" {
  // The original failure was Account admission before current_for. Retain its
  // exact typed refusal on the matching Native target; do not weaken admission.
  assert_eq(
    @authorization.admit_account_configuration_json(
      @utf8.decode(policy_account_original),
    ).map(_ => ()),
    Err(@authorization.NonCanonicalOrder("$.entries[0].resource.any_of[1]")),
  )
  let host = policy_host_fixture(
    "local-policy-reuse-closed",
    account_body=policy_reuse_account_original,
  )
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
  let host = policy_host_fixture(
    "local-policy-reuse-original",
    account_body=policy_reuse_account_original,
  )
  let other = policy_host_fixture(
    "local-policy-reuse-foreign",
    account_body=policy_reuse_account_original,
  )
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
