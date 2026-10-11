///|
// Pure typed adapter cases only. These literals are not an adopted Host,
// physical claim, approval or Provider acceptance evidence.
fn local_resource_test_scope() -> @credential.LocalCredentialScope {
  {
    account_configuration_cid: credential_test_cid("1"),
    account_id: "account-a",
    attempt_id: "attempt-original",
    authority_scope_cid: credential_test_cid("2"),
    connector_registration: "connector-a",
    connector_revision: "connector-a/1",
    fence_claimant: "owner-original",
    fence_generation: 7L,
    fence_intent_cid: credential_test_cid("3"),
    host_adoption_cid: credential_test_cid("4"),
    operation: "records:write",
    operation_occurrence_cid: credential_test_cid("5"),
    principal: "operator",
    request_body_cid: "sha256:037c9214eef74cc3887f3a4f085b4e17d76280dafd273b0ee160c09c4ba1cfd4",
    request_cid: credential_test_cid("6"),
    request_method: "PATCH",
    request_path: "/records/1",
    resource_origin: "https://resource.example",
    run_invocation_cid: credential_test_cid("7"),
    submission_scope_cid: credential_test_cid("8"),
    unit_definition_cid: credential_test_cid("9"),
  }
}

///|
fn local_resource_test_grant() -> @credential.LocalCredentialGrant {
  @credential.prepare_local_credential_grant(
    "local-authority-a",
    local_resource_test_scope(),
    2000000000000L,
    2,
  ).unwrap()
}

///|
fn local_resource_test_remote_grant(
  scope : NativeCredentialScope,
  max_uses? : Int = 2,
) -> @credential.RemoteCredentialGrant {
  @credential.prepare_grant(
    "credential-authority-a",
    scope.principal,
    scope.namespace_id,
    scope.environment,
    scope.site_key,
    scope.site_generation,
    scope.runtime_bundle_cid,
    scope.connector_registration,
    scope.connector_revision,
    scope.resource_origin,
    scope.operation,
    scope.run_invocation_cid,
    scope.task_attempt,
    scope.dispatch_request_cid,
    2000000000000L,
    max_uses,
  ).unwrap()
}

///|
test "Native typed credential adapter rejects Local and Remote scope substitution" {
  let local_grant = local_resource_test_grant()
  let local_scope = local_resource_test_scope()
  let remote_scope = credential_test_scope("https://resource.example")
  let remote = local_resource_test_remote_grant(remote_scope)
  assert_eq(
    owned_grant_matches_scope(LocalGrant(local_grant), LocalScope(local_scope)),
    Some((2, 2000000000000L)),
  )
  assert_eq(
    owned_grant_matches_scope(RemoteGrant(remote), RemoteScope(remote_scope)),
    Some((2, 2000000000000L)),
  )
  assert_eq(
    owned_grant_matches_scope(
      LocalGrant(local_grant),
      RemoteScope(remote_scope),
    ),
    None,
  )
  assert_eq(
    owned_grant_matches_scope(RemoteGrant(remote), LocalScope(local_scope)),
    None,
  )
  assert_true(
    prepare_owned_credential_use(
      LocalGrant(local_grant),
      "use-local",
      1999999999999L,
      0,
      false,
      RemoteScope(remote_scope),
    )
    is Err(@credential.CredentialGrantInactive),
  )
  let value = prepare_owned_credential_use(
    LocalGrant(local_grant),
    "use-local",
    1999999999999L,
    0,
    false,
    LocalScope(local_scope),
  ).unwrap()
  assert_true(
    authorize_owned_credential_use(
      value,
      1999999999999L,
      false,
      RemoteScope(remote_scope),
    )
    is Err(@credential.CredentialGrantInactive),
  )
  assert_eq(
    owned_credential_use_cid(value),
    "sha256:15e9c9cf97efcf7882842d5981276f096d4eb0e46371bd2ca34ca0f9b280c4d0",
  )
}

///|
test "Native typed credential adapter checks exact transport before claim" {
  let scope = local_resource_test_scope()
  assert_true(
    owned_request_matches_scope(
      LocalScope(scope),
      @http.Patch,
      "/records/1",
      b"{\"id\":1}",
    ),
  )
  assert_false(
    owned_request_matches_scope(
      LocalScope(scope),
      @http.Post,
      "/records/1",
      b"{\"id\":1}",
    ),
  )
  assert_false(
    owned_request_matches_scope(
      LocalScope(scope),
      @http.Patch,
      "/records/2",
      b"{\"id\":1}",
    ),
  )
  assert_false(
    owned_request_matches_scope(
      LocalScope(scope),
      @http.Patch,
      "/records/1",
      b"{\"id\":2}",
    ),
  )
  assert_false(
    owned_request_matches_scope(
      LocalScope(scope),
      @http.Patch,
      "/records/1",
      b"{\"id\":1} ",
    ),
  )
  for text in ["e\u0301\r\n", "é\r\n", "e\u0301\r", "e\u0301\n"] {
    let bytes = @utf8.encode(text)
    let changed = {
      ..scope,
      request_body_cid: @credential.local_credential_request_body_cid(bytes).unwrap(),
    }
    assert_true(
      owned_request_matches_scope(
        LocalScope(changed),
        @http.Patch,
        "/records/1",
        bytes,
      ),
    )
    assert_false(
      owned_request_matches_scope(
        LocalScope(changed),
        @http.Patch,
        "/records/1",
        b"{\"id\":1}",
      ),
    )
  }
}

///|
test "Native typed credential adapter restores original use without interpreting its outcome" {
  let local_grant = local_resource_test_grant()
  let scope = local_resource_test_scope()
  let value = prepare_owned_credential_use(
    LocalGrant(local_grant),
    "use-local",
    1999999999999L,
    0,
    false,
    LocalScope(scope),
  ).unwrap()
  let body = owned_credential_use_json(value).unwrap()
  let restored = admit_owned_credential_use(
    LocalGrant(local_grant),
    body,
    owned_credential_use_cid(value),
  ).unwrap()
  assert_eq(owned_credential_use_id(restored), "use-local")
  assert_true(owned_credential_use_matches_ordinal(restored, 1L))
  assert_false(owned_credential_use_matches_ordinal(restored, 2L))
  assert_eq(owned_credential_use_cid(restored), owned_credential_use_cid(value))
  assert_true(
    admit_owned_credential_use(
      LocalGrant(local_grant),
      body + " ",
      owned_credential_use_cid(value),
    )
    is Err(@credential.CredentialUseCollision),
  )
  assert_true(
    authorize_owned_credential_use(
      restored,
      2000000000000L,
      false,
      LocalScope(scope),
    )
    is Err(@credential.CredentialGrantInactive),
  )
  assert_true(
    authorize_owned_credential_use(
      restored,
      1999999999999L,
      true,
      LocalScope(scope),
    )
    is Err(@credential.CredentialGrantInactive),
  )
  assert_true(
    authorize_owned_credential_use(
      restored,
      1999999999999L,
      false,
      LocalScope({ ..scope, fence_generation: 8L, }),
    )
    is Err(@credential.CredentialGrantInactive),
  )
  let remote_scope = credential_test_scope("https://resource.example")
  assert_true(
    admit_owned_credential_use(
      RemoteGrant(local_resource_test_remote_grant(remote_scope)),
      body,
      owned_credential_use_cid(value),
    )
    is Err(@credential.CredentialUseCollision),
  )
}
