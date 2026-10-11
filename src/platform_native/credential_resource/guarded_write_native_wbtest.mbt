///|
test "Native guarded write checks execution authority after the final trusted clock" {
  // The existing Salesforce harness always supplies this actual HTTPS fixture.
  // Unrelated Core selections do not activate an optional physical endpoint.
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_URL")
    is Some(origin) else {
    return
  }
  let scope : NativeCredentialScope = {
    ..credential_test_scope(origin),
    site_generation: 4,
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    operation: "salesforce:record:update",
  }
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let database = sqlite
    .open_database(
      @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_TARGET_ROOT").unwrap() +
      "/write-guard-final-clock.sqlite",
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
  let path = "/services/data/v66.0/sobjects/ActQL_Test_Record__c/001000000000001"
  let grant = @credential.prepare_grant(
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
    1,
  ).unwrap()
  let mut clock_calls = 0
  let mut current = true
  let service = install_native_credential_resource_service_with_clock(
    database,
    client,
    [
      {
        resource_origin: origin,
        operation: scope.operation,
        path,
        secret_path: secret,
        verb: @http.Patch,
        max_request_bytes: 1024,
      },
    ],
    _ => true,
    fn() {
      clock_calls = clock_calls + 1
      if clock_calls == 3 {
        current = false
      }
      1791600000000L + clock_calls.to_int64()
    },
  ).unwrap()
  let mut guard_calls = 0
  assert_true(
    call_native_credential_resource_guarded_request_at_path(
      service,
      grant,
      "final-clock",
      scope,
      @http.Patch,
      path,
      b"{\"Optional_Value__c\":\"new\"}",
      fn() {
        guard_calls = guard_calls + 1
        current
      },
    )
    is Err(AccessDenied),
  )
  assert_eq(clock_calls, 3)
  assert_eq(guard_calls, 2)
  let status = query_native_credential_use(service, grant, "final-clock", scope).unwrap()
  assert_eq(status.outcome, "failed")
  assert_eq(status.status, None)
  ignore(client.close())
  database.close_checked().unwrap()
}

///|
// This explicitly selected physical adapter case supplies fixture authority,
// not an adopted Host, approved Effect or original Local Run. The HTTPS
// harness independently requires zero requests and writes for this selection.
test "Native retained credential claim never repairs missing Local or Remote use" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_DIRECT_LOCAL_CLAIM_CUSTODY")
    is Some("1") else {
    return
  }
  let origin = @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_URL").unwrap()
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let http = @http.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_LIBRARY").unwrap(),
  ).unwrap()
  let secret = @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_SECRET").unwrap()
  let path = "/services/data/v66.0/sobjects/ActQL_Test_Record__c/001000000000001"
  for domain in ["local", "remote"] {
    let database = sqlite
      .open_database(
        @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_TARGET_ROOT").unwrap() +
        "/retained-claim-" +
        domain +
        ".sqlite",
        65536L,
      )
      .unwrap()
    let client = http
      .create_authenticated_client(
        @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_CA").unwrap(),
        @http.Bearer(secret),
        1024L,
        2000,
        5000,
      )
      .unwrap()
    let direct_scope = {
      ..local_resource_test_scope(),
      resource_origin: origin,
      operation: "salesforce:record:update",
      request_path: path,
      // Independent SHA-256 of the exact authored fixture bytes below.
      request_body_cid: "sha256:6399fe49a070085db566de0c03e6098e3562ddf9348d1f81bca23ab0658c8e31",
    }
    let remote_scope = {
      ..credential_test_scope(origin),
      operation: direct_scope.operation,
    }
    let (grant, scope) : (
      NativeOwnedCredentialGrant,
      NativeOwnedCredentialScope,
    ) = if domain == "local" {
      (
        LocalGrant(
          @credential.prepare_local_credential_grant(
            "local-authority-a", direct_scope, 2000000000000L, 3,
          ).unwrap(),
        ),
        LocalScope(direct_scope),
      )
    } else {
      (
        RemoteGrant(local_resource_test_remote_grant(remote_scope, max_uses=3)),
        RemoteScope(remote_scope),
      )
    }
    let grant_cid = owned_credential_grant_cid(grant)
    // An ordinal alone is durable, but the separate use/original is absent.
    assert_eq(
      database
      .claim_ordinal(use_scope(grant_cid), "original-claim", 3L)
      .unwrap(),
      1L,
    )
    let stages : Array[String] = []
    let service = install_native_credential_resource_service_with_clock(
      database,
      client,
      [
        {
          resource_origin: origin,
          operation: direct_scope.operation,
          path,
          secret_path: secret,
          verb: @http.Patch,
          max_request_bytes: 1024,
        },
      ],
      fn(facts) {
        stages.push(facts.stage)
        true
      },
      () => 1791600000000L,
      authorize_local=Some(fn(facts) {
        stages.push(facts.stage)
        true
      }),
    ).unwrap()
    for _ in 0..<2 {
      assert_true(
        call_native_credential_resource_owned_scope(
          service,
          grant,
          "original-claim",
          scope,
          Some(path),
          @http.Patch,
          b"{\"Optional_Value__c\":\"new\"}",
          Some(() => true),
        )
        is Err(Journal(@sqlite.NotFound)),
      )
      assert_true(
        database.read(use_scope(grant_cid), "original-claim")
        is Err(@sqlite.NotFound),
      )
      assert_true(
        database.read(outcome_scope(grant_cid), "original-claim")
        is Err(@sqlite.NotFound),
      )
      assert_true(
        query_native_owned_credential_use(
          service, grant, "original-claim", scope,
        )
        is Err(Journal(@sqlite.NotFound)),
      )
    }
    assert_eq(stages, ["claim", "query", "claim", "query"])
    // A valid original use is observed, never resent. Its absent outcome is
    // the existing claimed state, not an inferred failure or unsent request.
    assert_eq(
      database.claim_ordinal(use_scope(grant_cid), "valid-use", 3L).unwrap(),
      2L,
    )
    let original_use = prepare_owned_credential_use(
      grant, "valid-use", 1791600000000L, 1, false, scope,
    ).unwrap()
    database
    .insert(
      use_scope(grant_cid),
      "valid-use",
      @utf8.encode(
        owned_credential_use_cid(original_use) +
        "\n" +
        owned_credential_use_json(original_use).unwrap(),
      ),
    )
    .unwrap()
    |> ignore
    assert_true(
      call_native_credential_resource_owned_scope(
        service,
        grant,
        "valid-use",
        scope,
        Some(path),
        @http.Patch,
        b"{\"Optional_Value__c\":\"new\"}",
        Some(() => true),
      )
      is Err(UseAlreadyClaimed),
    )
    let original_status = query_native_owned_credential_use(
      service, grant, "valid-use", scope,
    ).unwrap()
    assert_eq(original_status.outcome, "claimed")
    assert_eq(original_status.status, None)
    // Deliberately corrupted fixture custody is not replaced by admission.
    assert_eq(
      database.claim_ordinal(use_scope(grant_cid), "altered-use", 3L).unwrap(),
      3L,
    )
    database
    .insert(use_scope(grant_cid), "altered-use", b"altered-original")
    .unwrap()
    |> ignore
    assert_true(
      call_native_credential_resource_owned_scope(
        service,
        grant,
        "altered-use",
        scope,
        Some(path),
        @http.Patch,
        b"{\"Optional_Value__c\":\"new\"}",
        Some(() => true),
      )
      is Err(Journal(@sqlite.Collision)),
    )
    assert_true(
      query_native_owned_credential_use(service, grant, "altered-use", scope)
      is Err(Journal(@sqlite.Collision)),
    )
    assert_eq(
      database.read(use_scope(grant_cid), "altered-use").unwrap().body,
      b"altered-original",
    )
    assert_true(
      database.claim_ordinal_action(use_scope(grant_cid), "over-limit", 3L)
      is Err(@sqlite.CapacityExceeded),
    )
    assert_eq(stages, [
      "claim", "query", "claim", "query", "claim", "query", "return", "claim", "query",
    ])
    assert_true(
      database.claim_ordinal_action(use_scope(grant_cid), "original-claim", 3L)
      is Ok(@sqlite.Retained(1L)),
    )
    assert_true(client.close())
    database.close_checked().unwrap()
  }
}
