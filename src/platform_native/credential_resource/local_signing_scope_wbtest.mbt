///|
// Pure owned-purpose adapter cases. No service, database, key projection,
// current Allow or claim is constructed by these metadata-only fixtures.

///|
fn owned_signing_scope_fixture() -> @credential.LocalSigningCredentialScope {
  {
    account_configuration_cid: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    account_id: "fixture-account",
    attempt_id: "original-signing",
    authority_scope_cid: "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    checkpoint_cid: "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    checkpoint_id: "checkpoint_01",
    checkpoint_kind: @checkpoint.EffectSet,
    host_adoption_cid: "sha256:8888888888888888888888888888888888888888888888888888888888888888",
    key_configuration_cid: "sha256:9999999999999999999999999999999999999999999999999999999999999999",
    key_generation_cid: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    key_id: "reviewer-key",
    key_public_key_cid: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    preimage: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    principal: "é\r\n",
    request_cid: "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    request_scope_cid: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    run_definition_cid: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    run_invocation_cid: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
    submission_scope_cid: "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    unit_definition_cid: "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    purpose: @credential.ReviewerProof,
  }
}

///|
test "Owned signing metadata retains independent original use identity" {
  let scope = owned_signing_scope_fixture()
  let grant = @credential.prepare_local_signing_credential_grant(
    "original-host-issuer", scope, 1791970559138L, 1,
  ).unwrap()
  let owned = SigningGrant(grant)
  assert_eq(
    owned_credential_grant_cid(owned),
    "sha256:3a00533c843d11bd66205c306aa82f1f9f2a6dd9016d45b1889da31b8ca0959a",
  )
  assert_eq(
    owned_grant_matches_scope(owned, SigningScope(scope)),
    Some((1, 1791970559138L)),
  )
  let value = prepare_owned_credential_use(
    owned,
    "original-signing-use",
    1791970559137L,
    0,
    false,
    SigningScope(scope),
  ).unwrap()
  assert_eq(
    owned_credential_use_cid(value),
    "sha256:727d87273a8ce728124a15507129bb2a1e65c6438f85f5efee3d484b695b265f",
  )
  assert_eq(owned_credential_use_id(value), "original-signing-use")
  assert_true(owned_credential_use_matches_ordinal(value, 1L))
  assert_false(owned_credential_use_matches_ordinal(value, 2L))
  let wire = owned_credential_use_json(value).unwrap()
  let restored = admit_owned_credential_use(
    owned,
    wire,
    owned_credential_use_cid(value),
  ).unwrap()
  assert_eq(owned_credential_use_cid(restored), owned_credential_use_cid(value))
  assert_true(
    authorize_owned_credential_use(
      restored,
      1791970559137L,
      false,
      SigningScope(scope),
    )
    is Ok(_),
  )
  assert_true(
    authorize_owned_credential_use(
      restored,
      1791970559138L,
      false,
      SigningScope(scope),
    )
    is Err(@credential.CredentialGrantInactive),
  )
}

///|
test "Owned signing rejects HTTP and cross-purpose original substitution" {
  let scope = owned_signing_scope_fixture()
  let signing = SigningGrant(
    @credential.prepare_local_signing_credential_grant(
      "issuer", scope, 1000L, 1,
    ).unwrap(),
  )
  let local_scope = local_resource_test_scope()
  assert_eq(owned_grant_matches_scope(signing, LocalScope(local_scope)), None)
  assert_true(
    prepare_owned_credential_use(
      signing,
      "use",
      999L,
      0,
      false,
      LocalScope(local_scope),
    )
    is Err(@credential.CredentialGrantInactive),
  )
  assert_false(
    owned_request_matches_scope(
      SigningScope(scope),
      @http.Get,
      "/",
      @utf8.encode(""),
    ),
  )
  let signing_use = prepare_owned_credential_use(
    signing,
    "use",
    999L,
    0,
    false,
    SigningScope(scope),
  ).unwrap()
  assert_true(
    authorize_owned_credential_use(
      signing_use,
      999L,
      false,
      SigningScope({ ..scope, purpose: @credential.HostAttestation, }),
    )
    is Err(@credential.CredentialGrantInactive),
  )
  let local_grant = local_resource_test_grant()
  let http_use = @credential.prepare_local_credential_use(
    local_grant, "http-original", 999L, 0, false, local_scope,
  ).unwrap()
  assert_true(
    admit_owned_credential_use(
      signing,
      @credential.local_credential_use_json(http_use).unwrap(),
      @credential.local_credential_use_cid(http_use),
    )
    is Err(_),
  )
  assert_true(
    admit_owned_credential_use(
      LocalGrant(local_grant),
      owned_credential_use_json(signing_use).unwrap(),
      owned_credential_use_cid(signing_use),
    )
    is Err(_),
  )
}
