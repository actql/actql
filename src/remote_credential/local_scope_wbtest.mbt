///|
fn local_credential_fixture_scope() -> LocalCredentialScope {
  {
    account_configuration_cid: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    account_id: "account-a",
    attempt_id: "attempt-original",
    authority_scope_cid: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
    connector_registration: "connector-a",
    connector_revision: "connector-a/1",
    fence_claimant: "owner-original",
    fence_generation: 7L,
    fence_intent_cid: "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    host_adoption_cid: "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    operation: "records:write",
    operation_occurrence_cid: "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    principal: "operator",
    request_body_cid: "sha256:037c9214eef74cc3887f3a4f085b4e17d76280dafd273b0ee160c09c4ba1cfd4",
    request_cid: "sha256:6666666666666666666666666666666666666666666666666666666666666666",
    request_method: "PATCH",
    request_path: "/records/1",
    resource_origin: "https://resource.example",
    run_invocation_cid: "sha256:7777777777777777777777777777777777777777777777777777777777777777",
    submission_scope_cid: "sha256:8888888888888888888888888888888888888888888888888888888888888888",
    unit_definition_cid: "sha256:9999999999999999999999999999999999999999999999999999999999999999",
  }
}

///|
fn local_credential_fixture_grant() -> LocalCredentialGrant {
  prepare_local_credential_grant(
    "local-authority-a",
    local_credential_fixture_scope(),
    2000000000000L,
    2,
  ).unwrap()
}

///|
// Independent standard JSON/UTF-8/SHA-256 vectors for the declared field map.
// They are never updated from a product encoder or a successful test output.
let local_credential_expected_body = "{\"account_configuration_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"account_id\":\"account-a\",\"attempt_id\":\"attempt-original\",\"authority_scope_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"connector_registration\":\"connector-a\",\"connector_revision\":\"connector-a/1\",\"expires_unix_ms\":\"2000000000000\",\"fence_claimant\":\"owner-original\",\"fence_generation\":\"7\",\"fence_intent_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"host_adoption_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"issuer_authority\":\"local-authority-a\",\"max_uses\":2,\"operation\":\"records:write\",\"operation_occurrence_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"principal\":\"operator\",\"request_body_cid\":\"sha256:037c9214eef74cc3887f3a4f085b4e17d76280dafd273b0ee160c09c4ba1cfd4\",\"request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"request_method\":\"PATCH\",\"request_path\":\"/records/1\",\"resource_origin\":\"https://resource.example\",\"run_invocation_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"submission_scope_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"unit_definition_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-local-credential-grant/0.1\"}"

///|
let local_credential_expected_cid = "sha256:d2e42a0c51b75d996bf9c1c87e9b9fe99ea71048769f15393aec553efb8e5423"

///|
test "Local credential grant canonical body and identity are distinct from Remote" {
  let grant = local_credential_fixture_grant()
  assert_eq(
    local_credential_grant_json(grant),
    Ok(local_credential_expected_body),
  )
  assert_eq(local_credential_grant_cid(grant), local_credential_expected_cid)
  let restored = admit_local_credential_grant_json(
    local_credential_expected_body, local_credential_expected_cid,
  ).unwrap()
  assert_eq(
    local_credential_grant_scope(restored),
    local_credential_fixture_scope(),
  )
  assert_true(
    admit_grant_json(
      local_credential_expected_body, local_credential_expected_cid,
    )
    is Err(InvalidCredentialGrant),
  )
  let remote = credential_grant()
  assert_true(
    admit_local_credential_grant_json(
      credential_grant_json(remote).unwrap(),
      credential_grant_cid(remote),
    )
    is Err(InvalidCredentialGrant),
  )
  assert_eq(
    credential_grant_cid(remote),
    "sha256:06e4af5fa870fbe558c30211879440b84757b52e5d761cdb80f65c4b0eeb6d1c",
  )
  assert_true(
    admit_local_credential_grant_json(
      local_credential_expected_body + " ",
      local_credential_expected_cid,
    )
    is Err(InvalidCredentialGrant),
  )
  assert_true(
    admit_local_credential_grant_json(
      local_credential_expected_body,
      credential_cid("a"),
    )
    is Err(CredentialGrantIdentityMismatch),
  )
}

///|
test "Local credential use independent identity restores without consuming a new use" {
  let grant = local_credential_fixture_grant()
  let scope = local_credential_fixture_scope()
  let first = prepare_local_credential_use(
    grant, "use-local", 1999999999999L, 0, false, scope,
  ).unwrap()
  assert_eq(
    local_credential_use_json(first),
    Ok(
      "{\"grant_cid\":\"sha256:d2e42a0c51b75d996bf9c1c87e9b9fe99ea71048769f15393aec553efb8e5423\",\"use_id\":\"use-local\",\"use_ordinal\":1,\"version\":\"actql-local-credential-use/0.1\"}",
    ),
  )
  assert_eq(
    local_credential_use_cid(first),
    "sha256:15e9c9cf97efcf7882842d5981276f096d4eb0e46371bd2ca34ca0f9b280c4d0",
  )
  let restored = admit_local_credential_use_json(
    grant,
    local_credential_use_json(first).unwrap(),
    local_credential_use_cid(first),
  ).unwrap()
  assert_eq(
    local_credential_use_projection(restored),
    (local_credential_expected_cid, "use-local", 1),
  )
  assert_true(
    authorize_local_credential_use(restored, 1999999999999L, false, scope)
    is Ok(_),
  )
  assert_true(
    authorize_local_credential_use(restored, 2000000000000L, false, scope)
    is Err(CredentialGrantInactive),
  )
  assert_true(
    authorize_local_credential_use(restored, 1999999999999L, true, scope)
    is Err(CredentialGrantInactive),
  )
  assert_true(
    prepare_local_credential_use(
      grant, "use-next", 1999999999999L, 2, false, scope,
    )
    is Err(CredentialGrantInactive),
  )
  assert_true(
    admit_local_credential_use_json(
      grant,
      local_credential_use_json(first).unwrap() + " ",
      local_credential_use_cid(first),
    )
    is Err(CredentialUseCollision),
  )
  let remote = credential_grant()
  assert_true(
    admit_credential_use_json(
      remote,
      local_credential_use_json(first).unwrap(),
      local_credential_use_cid(first),
    )
    is Err(CredentialUseCollision),
  )
}

///|
test "Local credential use rejects each changed original binding at claim and send" {
  let grant = local_credential_fixture_grant()
  let scope = local_credential_fixture_scope()
  let first = prepare_local_credential_use(
    grant, "use-local", 1999999999999L, 0, false, scope,
  ).unwrap()
  let changed = [
    { ..scope, account_configuration_cid: credential_cid("a"), },
    { ..scope, account_id: "different", },
    { ..scope, attempt_id: "different", },
    { ..scope, authority_scope_cid: credential_cid("a"), },
    { ..scope, connector_registration: "different", },
    { ..scope, connector_revision: "different", },
    { ..scope, fence_claimant: "different", },
    { ..scope, fence_generation: 8L, },
    { ..scope, fence_intent_cid: credential_cid("a"), },
    { ..scope, host_adoption_cid: credential_cid("a"), },
    { ..scope, operation: "different", },
    { ..scope, operation_occurrence_cid: credential_cid("a"), },
    { ..scope, principal: "different", },
    { ..scope, request_body_cid: credential_cid("a"), },
    { ..scope, request_cid: credential_cid("a"), },
    { ..scope, request_method: "POST", },
    { ..scope, request_path: "different", },
    { ..scope, resource_origin: "https://different.example", },
    { ..scope, run_invocation_cid: credential_cid("a"), },
    { ..scope, submission_scope_cid: credential_cid("a"), },
    { ..scope, unit_definition_cid: credential_cid("a"), },
  ]
  for next in changed {
    assert_true(
      prepare_local_credential_use(
        grant, "use-next", 1999999999999L, 1, false, next,
      )
      is Err(CredentialGrantInactive),
    )
    assert_true(
      authorize_local_credential_use(first, 1999999999999L, false, next)
      is Err(CredentialGrantInactive),
    )
  }
}

///|
test "Local credential scopes refuse invalid fields oversized bounds and mixed domains" {
  let scope = local_credential_fixture_scope()
  for
    next in [
      { ..scope, host_adoption_cid: "site-a", },
      { ..scope, request_body_cid: "missing", },
      { ..scope, fence_generation: 0L, },
      { ..scope, fence_claimant: "", },
      { ..scope, attempt_id: "", },
      { ..scope, request_method: "CONNECT", },
      { ..scope, request_path: "//different.example/", },
      { ..scope, resource_origin: "https://user@resource.example", },
      { ..scope, request_method: "GET", },
    ] {
    assert_true(
      prepare_local_credential_grant(
        "local-authority-a", next, 2000000000000L, 2,
      )
      is Err(InvalidCredentialGrant),
    )
  }
  assert_true(
    prepare_local_credential_grant("local-authority-a", scope, 0L, 2)
    is Err(InvalidCredentialGrant),
  )
  assert_true(
    prepare_local_credential_grant(
      "local-authority-a", scope, 2000000000000L, 1025,
    )
    is Err(InvalidCredentialGrant),
  )
  let added = local_credential_expected_body.replace(
    old="\"version\"",
    new="\"site_key\":\"site-a\",\"version\"",
  )
  assert_true(
    admit_local_credential_grant_json(added, local_credential_expected_cid)
    is Err(InvalidCredentialGrant),
  )
}

///|
test "Local credential originals preserve Unicode and line endings rather than configuration normalization" {
  let scope = local_credential_fixture_scope()
  let decomposed = prepare_local_credential_grant(
    "local-authority-a",
    { ..scope, principal: "e\u0301\r\n", },
    2000000000000L,
    2,
  ).unwrap()
  let body = local_credential_grant_json(decomposed).unwrap()
  assert_eq(
    local_credential_grant_scope(
      admit_local_credential_grant_json(
        body,
        local_credential_grant_cid(decomposed),
      ).unwrap(),
    ).principal,
    "e\u0301\r\n",
  )
  for text in ["é\r\n", "e\u0301\r", "e\u0301\n"] {
    let changed = prepare_local_credential_grant(
      "local-authority-a",
      { ..scope, principal: text, },
      2000000000000L,
      2,
    ).unwrap()
    assert_false(
      local_credential_grant_cid(changed) ==
      local_credential_grant_cid(decomposed),
    )
  }
}

///|
test "Local credential request body identity preserves nested raw values and finite transport bounds" {
  let wire = "{\"nested\":{\"text\":\"é\\r\\n\"},\"explicit_null\":null}"
  assert_eq(
    local_credential_request_body_cid(@utf8.encode(wire)),
    Ok(
      "sha256:e94e518eb05145e133ac8f5c24b63ebb65194991b40841f0402f736d86703f5e",
    ),
  )
  for
    changed in [
      wire.replace(old="e\u0301", new="é"),
      wire.replace(old="\\r\\n", new="\\n"),
      wire.replace(old=",\"explicit_null\":null", new=""),
    ] {
    assert_false(
      local_credential_request_body_cid(@utf8.encode(changed)) ==
      local_credential_request_body_cid(@utf8.encode(wire)),
    )
  }
  assert_eq(
    local_credential_request_body_cid(b""),
    Ok(
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    ),
  )
  assert_true(
    local_credential_request_body_cid(@utf8.encode("x".repeat(65537)))
    is Err(InvalidCredentialGrant),
  )
}

///|
test "Remote credential use keeps its independent original preimage after shared record extraction" {
  let grant = credential_grant()
  let value = prepare_credential_use(
    grant,
    "use-a",
    1999999999999L,
    0,
    false,
    "principal-a",
    "namespace-a",
    "production",
    "site-a",
    4,
    credential_cid("a"),
    "http-source",
    "http-source/1",
    "https://resource.example",
    "records:read",
    credential_cid("b"),
    2,
    credential_cid("c"),
  ).unwrap()
  assert_eq(
    credential_use_json(value),
    Ok(
      "{\"grant_cid\":\"sha256:06e4af5fa870fbe558c30211879440b84757b52e5d761cdb80f65c4b0eeb6d1c\",\"use_id\":\"use-a\",\"use_ordinal\":1,\"version\":\"actql-remote-credential-use/0.1\"}",
    ),
  )
  assert_eq(
    credential_use_cid(value),
    "sha256:b9e78e6b665051eaf408d5875c5a7c7235e7c20f678822e1ac5761e979e1c326",
  )
}
