///|
fn signing_scope_fixture() -> LocalSigningCredentialScope {
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
    purpose: ReviewerProof,
  }
}

///|
test "Local signing reviewer_proof matches independent wire and CID" {
  let grant = prepare_local_signing_credential_grant(
    "original-host-issuer",
    { ..signing_scope_fixture(), purpose: ReviewerProof, },
    1791970559138L,
    1,
  ).unwrap()
  assert_eq(
    local_signing_credential_grant_json(grant),
    Ok(
      "{\"account_configuration_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"account_id\":\"fixture-account\",\"attempt_id\":\"original-signing\",\"authority_scope_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"checkpoint_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"checkpoint_id\":\"checkpoint_01\",\"checkpoint_kind\":\"effect_set\",\"expires_unix_ms\":\"1791970559138\",\"host_adoption_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"issuer_authority\":\"original-host-issuer\",\"key_configuration_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"key_generation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"key_id\":\"reviewer-key\",\"key_public_key_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"max_uses\":1,\"preimage\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"principal\":\"é\\r\\n\",\"purpose\":\"reviewer_proof\",\"request_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"request_scope_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"run_invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"submission_scope_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-local-signing-credential-grant/0.1\"}",
    ),
  )
  assert_eq(
    local_signing_credential_grant_cid(grant),
    "sha256:3a00533c843d11bd66205c306aa82f1f9f2a6dd9016d45b1889da31b8ca0959a",
  )
  assert_true(
    admit_local_signing_credential_grant_json(
      "{\"account_configuration_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"account_id\":\"fixture-account\",\"attempt_id\":\"original-signing\",\"authority_scope_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"checkpoint_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"checkpoint_id\":\"checkpoint_01\",\"checkpoint_kind\":\"effect_set\",\"expires_unix_ms\":\"1791970559138\",\"host_adoption_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"issuer_authority\":\"original-host-issuer\",\"key_configuration_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"key_generation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"key_id\":\"reviewer-key\",\"key_public_key_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"max_uses\":1,\"preimage\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"principal\":\"é\\r\\n\",\"purpose\":\"reviewer_proof\",\"request_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"request_scope_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"run_invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"submission_scope_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-local-signing-credential-grant/0.1\"}",
      "sha256:3a00533c843d11bd66205c306aa82f1f9f2a6dd9016d45b1889da31b8ca0959a",
    )
    is Ok(_),
  )
}

///|
test "Local signing host_attestation matches independent wire and CID" {
  let grant = prepare_local_signing_credential_grant(
    "original-host-issuer",
    {
      ..signing_scope_fixture(),
      purpose: HostAttestation,
      account_id: "fixture-host-account",
      authority_scope_cid: "sha256:" + "e".repeat(64),
      key_configuration_cid: "sha256:" + "0".repeat(64),
      key_generation_cid: "sha256:" + "1".repeat(64),
      key_id: "host-attestation-key",
      key_public_key_cid: "sha256:" + "2".repeat(64),
      principal: "host-attestor",
      preimage: "sha256:" + "b".repeat(64),
    },
    1791970559138L,
    1,
  ).unwrap()
  assert_eq(
    local_signing_credential_grant_json(grant),
    Ok(
      "{\"account_configuration_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"account_id\":\"fixture-host-account\",\"attempt_id\":\"original-signing\",\"authority_scope_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"checkpoint_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"checkpoint_id\":\"checkpoint_01\",\"checkpoint_kind\":\"effect_set\",\"expires_unix_ms\":\"1791970559138\",\"host_adoption_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"issuer_authority\":\"original-host-issuer\",\"key_configuration_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"key_generation_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"key_id\":\"host-attestation-key\",\"key_public_key_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"max_uses\":1,\"preimage\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"principal\":\"host-attestor\",\"purpose\":\"host_attestation\",\"request_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"request_scope_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"run_invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"submission_scope_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-local-signing-credential-grant/0.1\"}",
    ),
  )
  assert_eq(
    local_signing_credential_grant_cid(grant),
    "sha256:e07b383863ab35774691f464232bcb074fd7f68735fe897012fb4360a85b211a",
  )
  assert_true(
    admit_local_signing_credential_grant_json(
      "{\"account_configuration_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"account_id\":\"fixture-host-account\",\"attempt_id\":\"original-signing\",\"authority_scope_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"checkpoint_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"checkpoint_id\":\"checkpoint_01\",\"checkpoint_kind\":\"effect_set\",\"expires_unix_ms\":\"1791970559138\",\"host_adoption_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"issuer_authority\":\"original-host-issuer\",\"key_configuration_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"key_generation_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"key_id\":\"host-attestation-key\",\"key_public_key_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"max_uses\":1,\"preimage\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"principal\":\"host-attestor\",\"purpose\":\"host_attestation\",\"request_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"request_scope_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"run_invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"submission_scope_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-local-signing-credential-grant/0.1\"}",
      "sha256:e07b383863ab35774691f464232bcb074fd7f68735fe897012fb4360a85b211a",
    )
    is Ok(_),
  )
}

///|
test "Local signing roles and original key bindings do not share an identity" {
  let scope = signing_scope_fixture()
  let original = prepare_local_signing_credential_grant(
    "issuer", scope, 1000L, 1,
  ).unwrap()
  for
    changed in [
      { ..scope, purpose: HostAttestation, },
      { ..scope, key_generation_cid: "sha256:" + "0".repeat(64), },
      { ..scope, checkpoint_cid: "sha256:" + "b".repeat(64), },
      { ..scope, preimage: "sha256:" + "c".repeat(64), },
      { ..scope, run_definition_cid: "sha256:" + "d".repeat(64), },
    ] {
    let altered = prepare_local_signing_credential_grant(
      "issuer", changed, 1000L, 1,
    ).unwrap()
    assert_false(
      local_signing_credential_grant_cid(original) ==
      local_signing_credential_grant_cid(altered),
    )
    assert_true(
      admit_local_signing_credential_grant_json(
        local_signing_credential_grant_json(altered).unwrap(),
        local_signing_credential_grant_cid(original),
      )
      is Err(CredentialGrantIdentityMismatch),
    )
  }
}

///|
test "Local signing closed reader refuses unknown role HTTP fields and noncanonical bytes" {
  let grant = prepare_local_signing_credential_grant(
    "issuer",
    signing_scope_fixture(),
    1000L,
    1,
  ).unwrap()
  let wire = local_signing_credential_grant_json(grant).unwrap()
  for
    changed in [
      wire.replace_all(old="reviewer_proof", new="provider_sign"),
      wire.replace_all(old="{", new="{\"request_method\":\"GET\","),
      " " + wire,
    ] {
    assert_true(
      admit_local_signing_credential_grant_json(
        changed,
        local_signing_credential_grant_cid(grant),
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_local_signing_credential_grant(
      "issuer",
      { ..signing_scope_fixture(), preimage: "arbitrary text", },
      1000L,
      1,
    )
    is Err(InvalidCredentialGrant),
  )
  assert_true(
    prepare_local_signing_credential_grant(
      "issuer",
      signing_scope_fixture(),
      0L,
      1,
    )
    is Err(InvalidCredentialGrant),
  )
}

///|
test "Local signing use binding preserves purpose expiry and original ordinal" {
  let scope = signing_scope_fixture()
  let grant = prepare_local_signing_credential_grant("issuer", scope, 1000L, 1).unwrap()
  let value = prepare_local_signing_credential_use(
    grant, "original-use", 999L, 0, false, scope,
  ).unwrap()
  let wire = local_signing_credential_use_json(value).unwrap()
  assert_eq(
    local_signing_credential_use_projection(value),
    (local_signing_credential_grant_cid(grant), "original-use", 1),
  )
  let restored = admit_local_signing_credential_use_json(
    grant,
    wire,
    local_signing_credential_use_cid(value),
  ).unwrap()
  assert_eq(
    local_signing_credential_use_cid(restored),
    local_signing_credential_use_cid(value),
  )
  assert_true(
    validate_local_signing_credential_use_binding(value, 999L, false, scope)
    is Ok(_),
  )
  for
    changed in [
      { ..scope, purpose: HostAttestation, },
      { ..scope, checkpoint_kind: @checkpoint.ModelInvocation, },
      { ..scope, key_generation_cid: "sha256:" + "0".repeat(64), },
      { ..scope, request_scope_cid: "sha256:" + "e".repeat(64), },
    ] {
    assert_true(
      validate_local_signing_credential_use_binding(value, 999L, false, changed)
      is Err(CredentialGrantInactive),
    )
  }
  assert_true(
    prepare_local_signing_credential_use(
      grant, "original-use", 1000L, 0, false, scope,
    )
    is Err(CredentialGrantInactive),
  )
  assert_true(
    prepare_local_signing_credential_use(
      grant, "another-use", 999L, 1, false, scope,
    )
    is Err(CredentialGrantInactive),
  )
  assert_true(
    validate_local_signing_credential_use_binding(value, 999L, true, scope)
    is Err(CredentialGrantInactive),
  )
}
