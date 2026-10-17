///|
fn authentication_grant() -> RemoteCredentialGrant {
  prepare_grant(
    "credential-authority-a", "principal-a", "namespace-a", "production",
    "site-a", 4, credential_cid("a"), "http-source", "http-source/1",
    "https://oauth2.googleapis.com", "service-account:authenticate",
    credential_cid("b"), 2, credential_cid("c"), 1999999999999L, 1,
  ).unwrap()
}

///|
fn authentication_use(grant : RemoteCredentialGrant) -> RemoteCredentialUse {
  prepare_credential_use(
    grant, "original-use", 1L, 0, false, grant.principal, grant.namespace_id,
    grant.environment, grant.site_key, grant.site_generation,
    grant.runtime_bundle_cid, grant.connector_registration,
    grant.connector_revision, grant.resource_origin, grant.operation,
    grant.run_invocation_cid, grant.task_attempt, grant.dispatch_request_cid,
  ).unwrap()
}

///|
test "authentication binds separate grants and exact original uses and material" {
  let parent = authentication_use(credential_grant())
  let grant = authentication_grant()
  let material = [1]
  let body = b"bounded-private-form"
  let request = prepare_credential_authentication_request(
    parent, grant, material, "POST", "/token",
    "application/x-www-form-urlencoded", body, 64, 100L,
  ).unwrap()
  let credential_use = authentication_use(grant)
  let operation = bind_credential_authentication_use(
    request, parent, credential_use, material, "POST", "/token",
    "application/x-www-form-urlencoded", body, 1L,
  ).unwrap()
  assert_eq(
    check_credential_authentication_operation(
      operation, request, parent, credential_use, material, "POST", "/token",
      "application/x-www-form-urlencoded", body, 99L,
    ),
    Ok(()),
  )
  let another_request = prepare_credential_authentication_request(
    parent, grant, material, "POST", "/token",
    "application/x-www-form-urlencoded", body, 64, 100L,
  ).unwrap()
  assert_true(
    check_credential_authentication_operation(
      operation, another_request, parent, credential_use, material, "POST",
      "/token", "application/x-www-form-urlencoded", body, 1L,
    )
    is Err(CredentialGrantIdentityMismatch),
  )
  assert_true(
    check_credential_authentication_operation(
      operation, request, parent, credential_use, material, "POST", "/token",
      "application/x-www-form-urlencoded", body, 100L,
    )
    is Err(CredentialGrantInactive),
  )
  // Even equal canonical DATA cannot replace the original parent or auth use.
  let copied_parent = admit_credential_use_json(
    parent.grant, credential_use_json(parent).unwrap(), credential_use_cid(parent),
  ).unwrap()
  let copied_use = admit_credential_use_json(
    grant, credential_use_json(credential_use).unwrap(),
    credential_use_cid(credential_use),
  ).unwrap()
  for (candidate_parent, candidate_use, candidate_material) in [
    (copied_parent, credential_use, material),
    (parent, copied_use, material),
    (parent, credential_use, [1]),
  ] {
    assert_true(
      check_credential_authentication_operation(
        operation, request, candidate_parent, candidate_use, candidate_material,
        "POST", "/token", "application/x-www-form-urlencoded", body, 1L,
      )
      is Err(CredentialGrantIdentityMismatch),
    )
  }
  let copied_grant = admit_grant_json(
    credential_grant_json(grant).unwrap(), credential_grant_cid(grant),
  ).unwrap()
  assert_true(
    bind_credential_authentication_use(
      request, parent, authentication_use(copied_grant), material, "POST",
      "/token", "application/x-www-form-urlencoded", body, 1L,
    )
    is Err(CredentialGrantIdentityMismatch),
  )
}

///|
test "authentication rejects every foreign parent scope and grant retarget" {
  let parent = authentication_use(credential_grant())
  let grant = authentication_grant()
  let material = [1]
  for foreign in [
    { ..grant, issuer_authority: "foreign", },
    { ..grant, principal: "foreign", },
    { ..grant, namespace_id: "foreign", },
    { ..grant, environment: "foreign", },
    { ..grant, site_key: "foreign", },
    { ..grant, site_generation: 5, },
    { ..grant, runtime_bundle_cid: credential_cid("d"), },
    { ..grant, connector_registration: "foreign", },
    { ..grant, connector_revision: "foreign", },
    { ..grant, run_invocation_cid: credential_cid("d"), },
    { ..grant, task_attempt: 3, },
    { ..grant, dispatch_request_cid: credential_cid("d"), },
    { ..grant, expires_unix_ms: 2000000000001L, },
    parent.grant,
  ] {
    // Re-issue the DATA identity so this exercises scope, not a stale digest.
    let candidate = { ..foreign, grant_cid: grant_identity(foreign).unwrap(), }
    assert_true(
      prepare_credential_authentication_request(
        parent, candidate, material, "POST", "/token",
        "application/x-www-form-urlencoded", b"body", 64, 100L,
      )
      is Err(CredentialGrantIdentityMismatch),
    )
  }
}

///|
test "authentication bounds actual bytes before hashing and rejects request substitution" {
  let parent = authentication_use(credential_grant())
  let grant = authentication_grant()
  let material = [1]
  for (http_method, path, media, body, maximum, deadline) in [
    ("GET", "/token", "application/x-www-form-urlencoded", b"body", 4, 100L),
    ("POST", "/other", "application/x-www-form-urlencoded", b"body", 4, 100L),
    ("POST", "/token", "application/json", b"body", 4, 100L),
    ("POST", "/token", "application/x-www-form-urlencoded", b"", 4, 100L),
    ("POST", "/token", "application/x-www-form-urlencoded", b"body", 3, 100L),
    ("POST", "/token", "application/x-www-form-urlencoded", b"body", 0, 100L),
    ("POST", "/token", "application/x-www-form-urlencoded", b"body", 4, 0L),
    ("POST", "/token", "application/x-www-form-urlencoded", b"body", 4, 2000000000000L),
  ] {
    assert_true(
      prepare_credential_authentication_request(
        parent, grant, material, http_method, path, media, body, maximum, deadline,
      )
      is Err(InvalidCredentialGrant),
    )
  }
  let request = prepare_credential_authentication_request(
    parent, grant, material, "POST", "/token",
    "application/x-www-form-urlencoded", b"body", 4, 100L,
  ).unwrap()
  let credential_use = authentication_use(grant)
  for body in [b"BODY", b"body!"] {
    assert_true(
      bind_credential_authentication_use(
        request, parent, credential_use, material, "POST", "/token",
        "application/x-www-form-urlencoded", body, 1L,
      )
      is Err(CredentialGrantIdentityMismatch),
    )
  }
  for now in [-1L, 100L, 101L] {
    assert_true(
      bind_credential_authentication_use(
        request, parent, credential_use, material, "POST", "/token",
        "application/x-www-form-urlencoded", b"body", now,
      )
      is Err(CredentialGrantInactive),
    )
  }
}
