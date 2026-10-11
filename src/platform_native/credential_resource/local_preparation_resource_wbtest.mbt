///|
// Matching Native adapter diagnostics, not an adopted/started Host or public
// observation acceptance. Fixed grant/use CIDs were authored independently.
test "Native Preparation adapter keeps Remote Resume and Preparation domains distinct" {
  let preparation = native_preparation_identity_scope()
  let local_scope = local_resource_test_scope()
  let remote_scope = credential_test_scope("https://resource.example")
  let preparation_grant = @credential.prepare_local_preparation_credential_grant(
    "local-authority-a", preparation, 2000000000000L, 2,
  ).unwrap()
  let grants : Array[NativeOwnedCredentialGrant] = [
    RemoteGrant(local_resource_test_remote_grant(remote_scope)),
    LocalGrant(local_resource_test_grant()),
    PreparationGrant(preparation_grant),
  ]
  let scopes : Array[NativeOwnedCredentialScope] = [
    RemoteScope(remote_scope),
    LocalScope(local_scope),
    PreparationScope(preparation),
  ]
  for grant_index, grant in grants {
    for scope_index, scope in scopes {
      if grant_index == scope_index {
        assert_eq(
          owned_grant_matches_scope(grant, scope),
          Some((2, 2000000000000L)),
        )
      } else {
        assert_eq(owned_grant_matches_scope(grant, scope), None)
        assert_true(
          prepare_owned_credential_use(
            grant, "original", 1999999999999L, 0, false, scope,
          )
          is Err(@credential.CredentialGrantInactive),
        )
      }
    }
  }
  assert_eq(
    owned_credential_grant_cid(PreparationGrant(preparation_grant)),
    "sha256:f94a8a51a980cc764a6bc45f2e10805537effe1dc89e73991d119d8986ae41d2",
  )
}

///|
test "Native Preparation adapter refuses another target mutation or nonempty GET before use claim" {
  let preparation = native_preparation_identity_scope()
  let scope = PreparationScope(preparation)
  assert_true(
    owned_request_matches_scope(scope, @http.Get, preparation.request_path, b""),
  )
  for verb in [@http.Post, Put, Patch] {
    assert_false(
      owned_request_matches_scope(scope, verb, preparation.request_path, b""),
    )
  }
  assert_false(
    owned_request_matches_scope(
      scope,
      @http.Get,
      preparation.request_path + "-foreign",
      b"",
    ),
  )
  for bytes in [b" ", b"null", b"{}", b"\r\n"] {
    assert_false(
      owned_request_matches_scope(
        scope,
        @http.Get,
        preparation.request_path,
        bytes,
      ),
    )
  }
  assert_false(
    owned_request_matches_scope(
      PreparationScope({ ..preparation, operation: "salesforce:record:update", }),
      @http.Get,
      preparation.request_path,
      b"",
    ),
  )
}

///|
test "Native Preparation adapter restores the exact original use without another allowance" {
  let preparation = native_preparation_identity_scope()
  let grant = PreparationGrant(
    @credential.prepare_local_preparation_credential_grant(
      "local-authority-a", preparation, 2000000000000L, 2,
    ).unwrap(),
  )
  let scope = PreparationScope(preparation)
  let original = prepare_owned_credential_use(
    grant, "observe-use", 1999999999999L, 0, false, scope,
  ).unwrap()
  assert_eq(
    owned_credential_use_cid(original),
    "sha256:17f393ef1ac8c8fd7d86ddb27ae3f62869b6d3391bf1a1c040b10df8169443f8",
  )
  let body = owned_credential_use_json(original).unwrap()
  let restored = admit_owned_credential_use(
    grant,
    body,
    owned_credential_use_cid(original),
  ).unwrap()
  assert_eq(owned_credential_use_id(restored), "observe-use")
  assert_true(owned_credential_use_matches_ordinal(restored, 1L))
  assert_false(owned_credential_use_matches_ordinal(restored, 2L))
  assert_true(
    authorize_owned_credential_use(restored, 2000000000000L, false, scope)
    is Err(@credential.CredentialGrantInactive),
  )
  assert_true(
    authorize_owned_credential_use(restored, 1999999999999L, true, scope)
    is Err(@credential.CredentialGrantInactive),
  )
  for
    changed in [
      PreparationScope({ ..preparation, attempt_id: "other", }),
      LocalScope(local_resource_test_scope()),
      RemoteScope(credential_test_scope("https://resource.example")),
    ] {
    assert_true(
      authorize_owned_credential_use(restored, 1999999999999L, false, changed)
      is Err(@credential.CredentialGrantInactive),
    )
  }
  assert_true(
    admit_owned_credential_use(
      grant,
      body + " ",
      owned_credential_use_cid(original),
    )
    is Err(@credential.CredentialUseCollision),
  )
  assert_true(
    admit_owned_credential_use(
      LocalGrant(local_resource_test_grant()),
      body,
      owned_credential_use_cid(original),
    )
    is Err(@credential.CredentialUseCollision),
  )
}

///|
// Explicit fixture installation tests only. The matching Native harness must
// confirm zero HTTP requests; no public Host or operational Work is claimed.
test "Native Preparation installation never borrows Remote or Resume authorization" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_PREPARATION_CREDENTIAL")
    is Some("1") else {
    return
  }
  let origin = @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_URL").unwrap()
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let database = sqlite
    .open_database(
      @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_TARGET_ROOT").unwrap() +
      "/preparation-authorization.sqlite",
      65536L,
    )
    .unwrap()
  let http = @http.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_LIBRARY").unwrap(),
  ).unwrap()
  let secret = @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_SECRET").unwrap()
  let client = http
    .create_authenticated_client(
      @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_CA").unwrap(),
      @http.Bearer(secret),
      1024L,
      2000,
      5000,
    )
    .unwrap()
  let preparation = {
    ..native_preparation_identity_scope(),
    resource_origin: origin,
  }
  let operation : NativeCredentialOperation = {
    resource_origin: origin,
    operation: preparation.operation,
    path: preparation.request_path,
    secret_path: secret,
    verb: @http.Get,
    max_request_bytes: 0,
  }
  let remote_only = install_native_credential_resource_service(
    database,
    client,
    [operation],
    _ => true,
  ).unwrap()
  let local_only = install_native_local_credential_resource_service(
    database,
    client,
    [operation],
    _ => true,
  ).unwrap()
  let private_root = @filesystem.open_private_root(
    @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_TARGET_ROOT").unwrap(),
  ).unwrap()
  let secret_name = "preparation-bearer-" + @env.now().to_string()
  let writer = private_root.create_writer(secret_name, 32L).unwrap()
  writer.append(b"fixture-token\n").unwrap()
  writer.seal(secret_name + ".installed").unwrap() |> ignore
  let original_installation = private_root
    .adopt_private_file_projection(secret_name + ".installed")
    .unwrap()
  let prep_only = install_native_local_preparation_credential_resource_service(
    database,
    client,
    [{ operation, file: original_installation, }],
    _ => true,
  ).unwrap()
  let facts : NativeOwnedCredentialAuthorizationFacts = {
    stage: "claim",
    grant_cid: credential_test_cid("1"),
    use_cid: None,
    request: None,
  }
  assert_false(
    authorize_owned_credential(
      remote_only,
      PreparationScope(preparation),
      facts,
    ),
  )
  assert_false(
    authorize_owned_credential(local_only, PreparationScope(preparation), facts),
  )
  assert_false(
    authorize_owned_credential(
      prep_only,
      RemoteScope(credential_test_scope(origin)),
      facts,
    ),
  )
  assert_false(
    authorize_owned_credential(
      prep_only,
      LocalScope(local_resource_test_scope()),
      facts,
    ),
  )
  for
    changed in [
      { ..operation, operation: "salesforce:record:update", },
      { ..operation, verb: @http.Patch, },
      { ..operation, max_request_bytes: 1, },
    ] {
    assert_true(
      install_native_local_preparation_credential_resource_service(
        database,
        client,
        [{ operation: changed, file: original_installation, }],
        _ => true,
      )
      is Err(InvalidConfiguration),
    )
  }
  let grant = @credential.prepare_local_preparation_credential_grant(
    "local-authority-a", preparation, 2000000000000L, 2,
  ).unwrap()
  // Even an installed read callback cannot bypass the mandatory current Work
  // guard. Refusal occurs before ordinal claim or any Provider call.
  assert_true(
    call_native_local_preparation_credential_resource_guarded_request_at_path(
      prep_only,
      grant,
      "cancelled-before-entry",
      preparation,
      preparation.request_path,
      () => false,
    )
    is Err(AccessDenied),
  )
  assert_true(
    query_native_local_preparation_credential_use(
      prep_only, grant, "cancelled-before-entry", preparation,
    )
    is Err(Journal(@sqlite.NotFound)),
  )
  assert_true(
    database.read(
      use_scope(@credential.local_preparation_credential_grant_cid(grant)),
      "cancelled-before-entry",
    )
    is Err(@sqlite.NotFound),
  )
  // A valid current Work/installation without raw Store custody cannot use
  // the former unretained GET path. No ordinal or original use is consumed.
  assert_true(
    call_native_local_preparation_credential_resource_guarded_request_at_path(
      prep_only,
      grant,
      "missing-raw-before-entry",
      preparation,
      preparation.request_path,
      () => true,
    )
    is Err(InvalidConfiguration),
  )
  assert_true(
    database.read(
      use_scope(@credential.local_preparation_credential_grant_cid(grant)),
      "missing-raw-before-entry",
    )
    is Err(@sqlite.NotFound),
  )
  assert_true(client.close())
  writer.cancel().unwrap()
  database.close_checked().unwrap()
}
