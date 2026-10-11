///|
// Authored identity-only material. No Host, started Work, installation, grant
// adoption ACK or physical credential service is fabricated by this fixture.
fn preparation_callback_fixture() -> (
  @credential.LocalPreparationCredentialGrant,
  @credential_resource.NativeLocalPreparationCredentialAuthorization,
) {
  let cid = (value : String) => "sha256:" + value.repeat(64)
  let scope : @credential.LocalPreparationCredentialScope = {
    account_configuration_cid: cid("1"),
    account_id: "account-a",
    attempt_id: "observe-original",
    authority_scope_cid: cid("2"),
    connector_registration: "salesforce-a",
    connector_revision: "salesforce-a/1",
    preparation_fence: @credential.prepare_local_preparation_fence_identity({
      client_request_intent_cid: cid("6"),
      client_request_scope_cid: cid("2"),
      operation_occurrence_cid: cid("3"),
      run_invocation_cid: cid("4"),
      unit_definition_cid: cid("5"),
    }).unwrap(),
    host_adoption_cid: cid("4"),
    operation: "salesforce:record:observe",
    operation_occurrence_cid: cid("3"),
    principal: "operator",
    request_body_cid: "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    request_cid: cid("6"),
    request_method: "GET",
    request_path: "/services/data/v61.0/sobjects/Account/001-original",
    resource_origin: "https://resource.example",
    run_invocation_cid: cid("4"),
    submission_scope_cid: cid("2"),
    unit_definition_cid: cid("5"),
  }
  let grant = @credential.prepare_local_preparation_credential_grant(
    "local-authority-a", scope, 2000000000000L, 2,
  ).unwrap()
  let authorization : @credential_resource.NativeLocalPreparationCredentialAuthorization = {
    stage: "claim",
    grant_cid: @credential.local_preparation_credential_grant_cid(grant),
    use_cid: None,
    scope,
    request: Some({ verb: @http.Get, path: scope.request_path, body: b"", }),
  }
  (grant, authorization)
}

///|
test "Native preparation callback matches only its exact original claim and send request" {
  let (grant, original) = preparation_callback_fixture()
  assert_true(local_preparation_credential_request_matches(grant, original))
  assert_true(
    local_preparation_credential_request_matches(grant, {
      ..original,
      stage: "send",
      use_cid: Some("sha256:" + "7".repeat(64)),
    }),
  )
  // These true matches prove no authority or physical use. Production checks
  // the opaque ACK's current Work/read/issuer/immutable custody separately.
}

///|
test "Native preparation callback refuses foreign identity and non-original request bytes" {
  let (grant, original) = preparation_callback_fixture()
  let cid = "sha256:" + "9".repeat(64)
  for
    scope in [
      { ..original.scope, attempt_id: "other-attempt", },
      { ..original.scope, account_configuration_cid: cid, },
      { ..original.scope, host_adoption_cid: cid, },
      { ..original.scope, run_invocation_cid: cid, },
      { ..original.scope, submission_scope_cid: cid, },
      { ..original.scope, operation_occurrence_cid: cid, },
      { ..original.scope, request_cid: cid, },
      { ..original.scope, unit_definition_cid: cid, },
      { ..original.scope, principal: "other-operator", },
    ] {
    assert_false(
      local_preparation_credential_request_matches(grant, { ..original, scope, }),
    )
  }
  assert_false(
    local_preparation_credential_request_matches(grant, {
      ..original,
      grant_cid: cid,
    }),
  )
  let requests : Array[@credential_resource.NativeCredentialRequest?] = [
    None,
    Some({
      verb: @http.Get,
      path: original.scope.request_path + "2",
      body: b"",
    }),
    Some({ verb: @http.Post, path: original.scope.request_path, body: b"", }),
    Some({ verb: @http.Get, path: original.scope.request_path, body: b"x", }),
  ]
  for request in requests {
    assert_false(
      local_preparation_credential_request_matches(grant, {
        ..original,
        request,
      }),
    )
  }
}

///|
test "Native preparation callback cannot authorize query disclosure or malformed stage progression" {
  let (grant, original) = preparation_callback_fixture()
  for
    (stage, use_cid) in [
      ("query", None),
      ("return", Some("sha256:" + "7".repeat(64))),
      ("claim", Some("sha256:" + "7".repeat(64))),
      ("send", None),
      ("send", Some("")),
      ("unknown", None),
      ("raw-query", Some("sha256:" + "7".repeat(64))),
      ("raw-return", Some("sha256:" + "7".repeat(64))),
    ] {
    assert_false(
      local_preparation_credential_request_matches(grant, {
        ..original,
        stage,
        use_cid,
      }),
    )
  }
}

///|
test "Native preparation raw lookup has a distinct closed stage and original request domain" {
  let (grant, claim) = preparation_callback_fixture()
  let use_cid = "sha256:" + "7".repeat(64)
  for
    facts in [
      { ..claim, stage: "query", request: None, },
      { ..claim, stage: "return", use_cid: Some(use_cid), request: None, },
      { ..claim, stage: "raw-query", use_cid: Some(use_cid), },
      { ..claim, stage: "raw-return", use_cid: Some(use_cid), },
    ] {
    assert_true(local_preparation_raw_request_matches(grant, facts))
    assert_false(local_preparation_credential_request_matches(grant, facts))
  }
  // These authored matches confer no permission or response. The production
  // connection rechecks current Run/target read and immutable original custody.
  for
    (stage, original_use, request) in [
      ("claim", None, claim.request),
      ("send", Some(use_cid), claim.request),
      ("query", Some(use_cid), None),
      ("query", None, claim.request),
      ("return", None, None),
      ("return", Some(use_cid), claim.request),
      ("raw-query", None, claim.request),
      ("raw-return", Some(""), claim.request),
      ("raw-return", Some(use_cid), None),
      ("unknown", Some(use_cid), claim.request),
    ] {
    assert_false(
      local_preparation_raw_request_matches(grant, {
        ..claim,
        stage,
        use_cid: original_use,
        request,
      }),
    )
  }
}

///|
test "Native preparation raw read refuses another grant scope target verb or body" {
  let (grant, claim) = preparation_callback_fixture()
  let facts = {
    ..claim,
    stage: "raw-return",
    use_cid: Some("sha256:" + "7".repeat(64)),
  }
  let cid = "sha256:" + "9".repeat(64)
  assert_false(
    local_preparation_raw_request_matches(grant, { ..facts, grant_cid: cid, }),
  )
  for
    scope in [
      { ..facts.scope, attempt_id: "foreign-attempt", },
      { ..facts.scope, host_adoption_cid: cid, },
      { ..facts.scope, run_invocation_cid: cid, },
      { ..facts.scope, request_cid: cid, },
      { ..facts.scope, principal: "other-operator", },
    ] {
    assert_false(
      local_preparation_raw_request_matches(grant, { ..facts, scope, }),
    )
  }
  let requests : Array[@credential_resource.NativeCredentialRequest] = [
    { verb: @http.Post, path: facts.scope.request_path, body: b"", },
    { verb: @http.Get, path: facts.scope.request_path + "-other", body: b"", },
    { verb: @http.Get, path: facts.scope.request_path, body: b"null", },
  ]
  for request in requests {
    assert_false(
      local_preparation_raw_request_matches(grant, {
        ..facts,
        request: Some(request),
      }),
    )
  }
}
