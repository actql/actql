///|
// Matching Native API consumer diagnostics. These pure identities do not provide
// an operational Work witness, installed credential, current permission or I/O.
fn native_preparation_identity_scope() -> @credential.LocalPreparationCredentialScope {
  let fence = @credential.prepare_local_preparation_fence_identity({
    client_request_intent_cid: credential_test_cid("1"),
    client_request_scope_cid: credential_test_cid("2"),
    operation_occurrence_cid: credential_test_cid("3"),
    run_invocation_cid: credential_test_cid("4"),
    unit_definition_cid: credential_test_cid("5"),
  }).unwrap()
  {
    account_configuration_cid: credential_test_cid("1"),
    account_id: "account-a",
    attempt_id: "observe-original",
    authority_scope_cid: credential_test_cid("2"),
    connector_registration: "salesforce-a",
    connector_revision: "salesforce-a/1",
    preparation_fence: fence,
    host_adoption_cid: credential_test_cid("4"),
    operation: "salesforce:record:observe",
    operation_occurrence_cid: credential_test_cid("3"),
    principal: "operator",
    request_body_cid: "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    request_cid: credential_test_cid("6"),
    request_method: "GET",
    request_path: "/services/data/v61.0/sobjects/Account/001-original",
    resource_origin: "https://resource.example",
    run_invocation_cid: credential_test_cid("4"),
    submission_scope_cid: credential_test_cid("2"),
    unit_definition_cid: credential_test_cid("5"),
  }
}

///|
test "Native preparation grant consumer admits the exact original and rejects mutation or foreign Work identity" {
  let scope = native_preparation_identity_scope()
  let grant = @credential.prepare_local_preparation_credential_grant(
    "local-authority-a", scope, 2000000000000L, 2,
  ).unwrap()
  assert_eq(
    @credential.local_preparation_credential_grant_cid(grant),
    "sha256:f94a8a51a980cc764a6bc45f2e10805537effe1dc89e73991d119d8986ae41d2",
  )
  let restored = @credential.admit_local_preparation_credential_grant_json(
    @credential.local_preparation_credential_grant_json(grant).unwrap(),
    @credential.local_preparation_credential_grant_cid(grant),
    scope.preparation_fence,
  ).unwrap()
  assert_eq(
    @credential.local_preparation_credential_grant_scope(restored),
    scope,
  )
  for
    changed in [
      { ..scope, request_method: "PATCH", },
      { ..scope, operation: "salesforce:record:patch", },
      { ..scope, submission_scope_cid: credential_test_cid("a"), },
      { ..scope, operation_occurrence_cid: credential_test_cid("a"), },
    ] {
    assert_true(
      @credential.prepare_local_preparation_credential_grant(
        "local-authority-a", changed, 2000000000000L, 2,
      )
      is Err(@credential.InvalidCredentialGrant),
    )
  }
  assert_true(
    @credential.admit_local_credential_grant_json(
      @credential.local_preparation_credential_grant_json(grant).unwrap(),
      @credential.local_preparation_credential_grant_cid(grant),
    )
    is Err(@credential.InvalidCredentialGrant),
  )
}

///|
test "Native preparation use consumer restores one exact use without renewal or resume substitution" {
  let scope = native_preparation_identity_scope()
  let grant = @credential.prepare_local_preparation_credential_grant(
    "local-authority-a", scope, 2000000000000L, 2,
  ).unwrap()
  let use = @credential.prepare_local_preparation_credential_use(
    grant, "observe-use", 1999999999999L, 0, false, scope,
  ).unwrap()
  assert_eq(
    @credential.local_preparation_credential_use_cid(use),
    "sha256:17f393ef1ac8c8fd7d86ddb27ae3f62869b6d3391bf1a1c040b10df8169443f8",
  )
  let restored = @credential.admit_local_preparation_credential_use_json(
    grant,
    @credential.local_preparation_credential_use_json(use).unwrap(),
    @credential.local_preparation_credential_use_cid(use),
  ).unwrap()
  assert_eq(
    @credential.local_preparation_credential_use_projection(restored),
    (
      @credential.local_preparation_credential_grant_cid(grant),
      "observe-use",
      1,
    ),
  )
  assert_true(
    @credential.authorize_local_preparation_credential_use(
      restored, 2000000000000L, false, scope,
    )
    is Err(@credential.CredentialGrantInactive),
  )
  assert_true(
    @credential.authorize_local_preparation_credential_use(
      restored, 1999999999999L, true, scope,
    )
    is Err(@credential.CredentialGrantInactive),
  )
  assert_true(
    @credential.authorize_local_preparation_credential_use(
      restored,
      1999999999999L,
      false,
      { ..scope, attempt_id: "other", },
    )
    is Err(@credential.CredentialGrantInactive),
  )
}
