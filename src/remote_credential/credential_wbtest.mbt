///|
fn credential_cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
fn credential_grant() -> RemoteCredentialGrant {
  prepare_grant(
    "credential-authority-a",
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
    2000000000000L,
    2,
  ).unwrap()
}

///|
test "credential grant has a canonical identity without secret material" {
  let grant = credential_grant()
  let body = credential_grant_json(grant).unwrap()
  assert_eq(
    body, "{\"connector_registration\":\"http-source\",\"connector_revision\":\"http-source/1\",\"dispatch_request_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"environment\":\"production\",\"expires_unix_ms\":\"2000000000000\",\"issuer_authority\":\"credential-authority-a\",\"max_uses\":2,\"operation\":\"records:read\",\"principal\":\"principal-a\",\"resource_origin\":\"https://resource.example\",\"run_invocation_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"runtime_bundle_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"site_generation\":4,\"site_key\":\"site-a\",\"task_attempt\":2,\"namespace_id\":\"namespace-a\",\"version\":\"actql-remote-credential-grant/0.1\"}",
  )
  assert_false(body.contains("secret"))
  assert_eq(
    credential_grant_cid(grant),
    "sha256:b653489c9b3dcacbfc7cd249015fa1fbc7194c1df1bf28fdb72e7a437e94f3cf",
  )
  assert_eq(
    credential_grant_cid(
      admit_grant_json(body, credential_grant_cid(grant)).unwrap(),
    ),
    credential_grant_cid(grant),
  )
  assert_true(
    admit_grant_json(body + " ", credential_grant_cid(grant))
    is Err(InvalidCredentialGrant),
  )
  let prior = body.replace(old="namespace_id", new="tenant")
  assert_true(
    admit_grant_json(prior, credential_grant_cid(grant))
    is Err(InvalidCredentialGrant),
  )
  let mixed = body.replace(
    old="\"version\"",
    new="\"tenant\":\"namespace-a\",\"version\"",
  )
  assert_true(
    admit_grant_json(mixed, credential_grant_cid(grant))
    is Err(InvalidCredentialGrant),
  )
}

///|
test "credential signature envelope has one canonical MoonBit preimage" {
  let grant = credential_grant()
  let signature = "A".repeat(86)
  let envelope = prepare_credential_signature_envelope(
    grant, "credential-key-a", signature,
  ).unwrap()
  let projection = credential_signature_envelope_projection(envelope)
  assert_eq(projection, [
    "actql-remote-credential-grant-signature/0.1",
    "credential-key-a",
    credential_grant_cid(grant),
    credential_grant_json(grant).unwrap(),
    signature,
    "credential-authority-a",
  ])
  assert_eq(
    credential_grant_signature_preimage(grant).unwrap(),
    @utf8.encode(
      "actql-remote-credential-grant-signature/0.1\u{0000}" +
      credential_grant_cid(grant) +
      "\u{0000}" +
      credential_grant_json(grant).unwrap(),
    ),
  )
  let admitted = admit_credential_signature_envelope(
    projection[0],
    projection[1],
    projection[2],
    projection[3],
    projection[4],
  ).unwrap()
  assert_eq(
    credential_grant_cid(credential_signature_envelope_grant(admitted)),
    credential_grant_cid(grant),
  )
  assert_true(
    admit_credential_signature_envelope(
      "actql-remote-credential-grant-signature/0.2",
      projection[1],
      projection[2],
      projection[3],
      projection[4],
    )
    is Err(InvalidCredentialSignature),
  )
}

///|
test "credential use binds exact scope expiry revocation and ordinal" {
  let grant = credential_grant()
  let first = prepare_credential_use(
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
  assert_eq(credential_use_projection(first)[3], "1")
  let use_body = credential_use_json(first).unwrap()
  assert_eq(
    credential_use_cid(
      admit_credential_use_json(grant, use_body, credential_use_cid(first)).unwrap(),
    ),
    credential_use_cid(first),
  )
  assert_true(
    admit_credential_use_json(grant, use_body + " ", credential_use_cid(first))
    is Err(CredentialUseCollision),
  )
  assert_eq(
    authorize_credential_use(
      first,
      1999999999999L,
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
    ),
    Ok(()),
  )
  assert_true(
    prepare_credential_use(
      grant,
      "use-b",
      2000000000000L,
      1,
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
    )
    is Err(CredentialGrantInactive),
  )
  assert_true(
    prepare_credential_use(
      grant,
      "use-b",
      1999999999999L,
      1,
      true,
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
    )
    is Err(CredentialGrantInactive),
  )
  assert_true(
    prepare_credential_use(
      grant,
      "use-b",
      1999999999999L,
      1,
      false,
      "principal-a",
      "namespace-a",
      "production",
      "site-a",
      4,
      credential_cid("a"),
      "http-source",
      "http-source/1",
      "https://other.example",
      "records:read",
      credential_cid("b"),
      2,
      credential_cid("c"),
    )
    is Err(CredentialGrantInactive),
  )
}
