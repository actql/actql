///|
// Definitions only until a matching Native fixture is allocated and executed.
test "Native policy material is fresh per predicate and unavailable after original Host close" {
  let host = policy_host_fixture("local-policy-reuse-closed")
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
  let host = policy_host_fixture("local-policy-reuse-original")
  let other = policy_host_fixture("local-policy-reuse-foreign")
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
