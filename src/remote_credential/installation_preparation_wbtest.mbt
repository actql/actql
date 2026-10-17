///|
fn installation_subject_fields() -> InstallationPreparationSubjectFields {
  {
    account_configuration_cid: "sha256:" + "a".repeat(64),
    account_id: "account",
    connection: "notion",
    connector_registration: "notion",
    connector_revision: "original",
    declaration_source_cid: "sha256:" + "b".repeat(64),
    installation_request_id: "publication-1",
    principal: "actor",
    runtime_bundle_cid: "sha256:" + "c".repeat(64),
    site_generation: 1,
    site_key: "site",
  }
}

///|
fn installation_scope() -> InstallationPreparationCredentialScope {
  {
    subject: prepare_installation_preparation_subject(
      installation_subject_fields(),
    ).unwrap(),
    metadata_occurrence_id: "database-1",
    operation: "notion:databases:retrieve",
    request_body_cid: "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    request_method: "GET",
    request_path: "/v1/databases/original",
    resource_origin: "https://api.notion.com",
  }
}

///|
fn installation_grant(
  scope : InstallationPreparationCredentialScope,
) -> InstallationPreparationCredentialGrant {
  prepare_installation_preparation_credential_grant("issuer", scope, 100L, 1).unwrap()
}

///|
test "installation subject canonical source identity is not a Run or semantic declaration CID" {
  let subject = installation_scope().subject
  assert_eq(
    subject.original_wire(),
    "{\"account_configuration_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"account_id\":\"account\",\"connection\":\"notion\",\"connector_registration\":\"notion\",\"connector_revision\":\"original\",\"declaration_source_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"installation_request_id\":\"publication-1\",\"principal\":\"actor\",\"runtime_bundle_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"site_generation\":1,\"site_key\":\"site\",\"version\":\"actql-installation-metadata-preparation/0.1\"}",
  )
  assert_eq(
    subject.cid(),
    "sha256:8309e3424c939bbbd221c7012401095fb9763f1f5ea09be659e9346439d8090c",
  )
  assert_eq(
    admit_installation_preparation_subject_json(
      subject.original_wire(),
      subject.cid(),
    )
    .unwrap()
    .fields(),
    installation_subject_fields(),
  )
  assert_false(subject.original_wire().contains("run_invocation_cid"))
  assert_false(subject.original_wire().contains("host_adoption_cid"))
}

///|
test "installation subject refuses missing foreign noncanonical and unbounded originals" {
  let subject = installation_scope().subject
  for
    body in [
      subject.original_wire() + " ",
      subject
      .original_wire()
      .replace(old="\"site_generation\":1", new="\"site_generation\":-1"),
      subject
      .original_wire()
      .replace(
        old="\"version\"",
        new="\"run_invocation_cid\":\"foreign\",\"version\"",
      ),
      subject
      .original_wire()
      .replace(old="declaration_source_cid", new="declaration_cid"),
    ] {
    assert_true(
      admit_installation_preparation_subject_json(body, subject.cid()) is Err(_),
    )
  }
  assert_true(
    admit_installation_preparation_subject_json(
      subject.original_wire(),
      "sha256:" + "0".repeat(64),
    )
    is Err(CredentialGrantIdentityMismatch),
  )
  for
    fields in [
      { ..subject.fields(), account_id: "", },
      { ..subject.fields(), principal: "actor\u{0}", },
      { ..subject.fields(), installation_request_id: "r".repeat(257), },
      { ..subject.fields(), runtime_bundle_cid: "runtime", },
    ] {
    assert_true(prepare_installation_preparation_subject(fields) is Err(_))
  }
}

///|
test "installation grant exact independent preimage keeps old Run reader closed" {
  let scope = installation_scope()
  assert_true(installation_preparation_scope_valid(scope))
  let direct : InstallationPreparationCredentialGrant = {
    issuer_authority: "issuer",
    scope,
    expires_unix_ms: 100L,
    max_uses: 1,
    identity: "diagnostic",
  }
  let _ = emit_installation_preparation_grant_body(direct)
  let grant = installation_grant(scope)
  let body = grant.original_wire().unwrap()
  assert_eq(
    body, "{\"expires_unix_ms\":\"100\",\"issuer_authority\":\"issuer\",\"max_uses\":1,\"metadata_occurrence_id\":\"database-1\",\"operation\":\"notion:databases:retrieve\",\"preparation_subject_cid\":\"sha256:8309e3424c939bbbd221c7012401095fb9763f1f5ea09be659e9346439d8090c\",\"request_body_cid\":\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\",\"request_method\":\"GET\",\"request_path\":\"/v1/databases/original\",\"resource_origin\":\"https://api.notion.com\",\"subject_kind\":\"installation_metadata\",\"version\":\"actql-installation-preparation-credential-grant/0.1\"}",
  )
  assert_eq(
    grant.cid(),
    "sha256:55de793a54db8e911d2f767984c4bd6d254c37a2808c4a01e3c36b512fec1c1b",
  )
  assert_true(physical_equal(grant.scope().subject, scope.subject))
  assert_true(admit_grant_json(body, grant.cid()) is Err(_))
  assert_true(
    physical_equal(
      admit_installation_preparation_credential_grant_json(
        scope.subject,
        body,
        grant.cid(),
      )
      .unwrap()
      .scope().subject,
      scope.subject,
    ),
  )
  for
    wrong in [
      body + " ",
      body.replace(old="installation_metadata", new="run"),
      body.replace(
        old="\"request_method\":\"GET\"",
        new="\"request_method\":\"POST\"",
      ),
    ] {
    assert_true(
      admit_installation_preparation_credential_grant_json(
        scope.subject,
        wrong,
        grant.cid(),
      )
      is Err(_),
    )
  }
}

///|
test "installation metadata scope refuses body mutation path ambiguity and invalid quota" {
  let scope = installation_scope()
  for
    wrong in [
      { ..scope, request_method: "POST", },
      { ..scope, request_path: "//foreign/path", },
      { ..scope, request_path: "/path?selector=foreign", },
      { ..scope, request_path: "/path\r\nforeign", },
      { ..scope, resource_origin: "https://user@api.notion.com", },
      { ..scope, request_body_cid: "sha256:" + "a".repeat(64), },
    ] {
    assert_true(
      prepare_installation_preparation_credential_grant(
        "issuer", wrong, 100L, 1,
      )
      is Err(InvalidCredentialGrant),
    )
  }
  assert_true(
    prepare_installation_preparation_credential_grant("issuer", scope, 0L, 1)
    is Err(_),
  )
  assert_true(
    prepare_installation_preparation_credential_grant("issuer", scope, 100L, 0)
    is Err(_),
  )
}

///|
test "installation use rejects copied subject and each foreign occurrence dimension" {
  let scope = installation_scope()
  let grant = installation_grant(scope)
  let copy = admit_installation_preparation_subject_json(
    scope.subject.original_wire(),
    scope.subject.cid(),
  ).unwrap()
  assert_eq(copy.cid(), scope.subject.cid())
  assert_false(physical_equal(copy, scope.subject))
  for
    actual in [
      { ..scope, subject: copy, },
      { ..scope, subject: installation_scope().subject, },
      { ..scope, metadata_occurrence_id: "schema-1", },
      { ..scope, operation: "notion:data-sources:retrieve", },
      { ..scope, operation: "notion:data-sources:query", },
      { ..scope, request_method: "POST", },
      { ..scope, request_path: "/v1/databases/foreign", },
      { ..scope, resource_origin: "https://foreign.example", },
      { ..scope, request_body_cid: "sha256:" + "a".repeat(64), },
    ] {
    assert_true(
      prepare_installation_preparation_credential_use(
        grant, "use-1", 1L, 0, false, actual,
      )
      is Err(CredentialGrantInactive),
    )
  }
  let fields = scope.subject.fields()
  for
    foreign in [
      { ..fields, account_configuration_cid: "sha256:" + "d".repeat(64), },
      { ..fields, account_id: "foreign", },
      { ..fields, connection: "foreign", },
      { ..fields, connector_registration: "foreign", },
      { ..fields, connector_revision: "next", },
      { ..fields, declaration_source_cid: "sha256:" + "d".repeat(64), },
      { ..fields, installation_request_id: "publication-2", },
      { ..fields, principal: "foreign", },
      { ..fields, runtime_bundle_cid: "sha256:" + "d".repeat(64), },
      { ..fields, site_generation: 2, },
      { ..fields, site_key: "foreign", },
    ] {
    assert_true(
      prepare_installation_preparation_credential_use(
        grant,
        "use-1",
        1L,
        0,
        false,
        {
          ..scope,
          subject: prepare_installation_preparation_subject(foreign).unwrap(),
        },
      )
      is Err(CredentialGrantInactive),
    )
  }
}

///|
test "installation use retains original subject clock revocation and quota boundaries" {
  let scope = installation_scope()
  let grant = installation_grant(scope)
  let value = prepare_installation_preparation_credential_use(
    grant, "use-1", 99L, 0, false, scope,
  ).unwrap()
  assert_eq(
    value.cid(),
    "sha256:d9526bec4b56579a641eb0351a01bde77f3a1ae84b74f3c6ca1a363af904b534",
  )
  assert_eq(
    value.original_wire().unwrap(),
    "{\"grant_cid\":\"sha256:55de793a54db8e911d2f767984c4bd6d254c37a2808c4a01e3c36b512fec1c1b\",\"use_id\":\"use-1\",\"use_ordinal\":1,\"version\":\"actql-remote-credential-use/0.1\"}",
  )
  assert_eq(
    authorize_installation_preparation_credential_use(value, 99L, false, scope),
    Ok(()),
  )
  for now in [-1L, 100L] {
    assert_true(
      prepare_installation_preparation_credential_use(
        grant, "use-1", now, 0, false, scope,
      )
      is Err(_),
    )
    assert_true(
      authorize_installation_preparation_credential_use(
        value, now, false, scope,
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_installation_preparation_credential_use(
      grant, "use-1", 1L, 1, false, scope,
    )
    is Err(_),
  )
  assert_true(
    prepare_installation_preparation_credential_use(
      grant, "use-1", 1L, 0, true, scope,
    )
    is Err(_),
  )
  assert_true(
    authorize_installation_preparation_credential_use(value, 1L, true, scope)
    is Err(_),
  )
  assert_true(
    authorize_installation_preparation_credential_use(value, 1L, false, {
      ..scope,
      operation: "notion:data-sources:query",
    })
    is Err(_),
  )
}

///|
test "installation cold use DATA preserves original grant and rejects substituted material" {
  let scope = installation_scope()
  let grant = installation_grant(scope)
  let value = prepare_installation_preparation_credential_use(
    grant, "use-1", 1L, 0, false, scope,
  ).unwrap()
  let admitted = admit_installation_preparation_credential_use_json(
    grant,
    value.original_wire().unwrap(),
    value.cid(),
  ).unwrap()
  assert_eq(admitted.projection(), value.projection())
  assert_true(physical_equal(admitted.grant, grant))
  for
    body in [
      value.original_wire().unwrap() + " ",
      value
      .original_wire()
      .unwrap()
      .replace(old="\"use_ordinal\":1", new="\"use_ordinal\":0"),
      value
      .original_wire()
      .unwrap()
      .replace(old="\"use_ordinal\":1", new="\"use_ordinal\":2"),
      value
      .original_wire()
      .unwrap()
      .replace(old="\"version\"", new="\"run\":\"foreign\",\"version\""),
    ] {
    assert_true(
      admit_installation_preparation_credential_use_json(
        grant,
        body,
        value.cid(),
      )
      is Err(_),
    )
  }
  let other = installation_grant({
    ..scope,
    metadata_occurrence_id: "schema-1",
  })
  assert_true(
    admit_installation_preparation_credential_use_json(
      other,
      value.original_wire().unwrap(),
      value.cid(),
    )
    is Err(_),
  )
}

///|
test "installation signature uses existing exact envelope domain without old Run admission" {
  let scope = installation_scope()
  let grant = installation_grant(scope)
  let signature = "A".repeat(86)
  let envelope = prepare_installation_preparation_credential_signature_envelope(
    grant, "key", signature,
  ).unwrap()
  assert_eq(
    installation_preparation_credential_signature_preimage(grant).unwrap(),
    @utf8.encode(
      "actql-remote-credential-grant-signature/0.1\u{0}" +
      grant.cid() +
      "\u{0}" +
      grant.original_wire().unwrap(),
    ),
  )
  let (version, key, cid, body, signed, issuer) = envelope.projection()
  assert_eq(issuer, "issuer")
  assert_eq(signed, signature)
  assert_true(physical_equal(envelope.grant(), grant))
  assert_true(
    admit_credential_signature_envelope(version, key, cid, body, signed)
    is Err(_),
  )
  let decoded = admit_installation_preparation_credential_signature_envelope(
    scope.subject,
    version,
    key,
    cid,
    body,
    signed,
  ).unwrap()
  assert_true(physical_equal(decoded.grant().scope().subject, scope.subject))
  assert_true(
    admit_installation_preparation_credential_signature_envelope(
      scope.subject,
      "wrong",
      key,
      cid,
      body,
      signed,
    )
    is Err(_),
  )
  assert_true(
    prepare_installation_preparation_credential_signature_envelope(
      grant, "key", "invalid",
    )
    is Err(InvalidCredentialSignature),
  )
}
