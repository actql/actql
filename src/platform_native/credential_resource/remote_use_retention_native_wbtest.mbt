///|
/// Uses the existing physical credential fixture. These cases must not become
/// passing early returns when that fixture is unavailable.
fn remote_retention_physical_fixture(
  suffix : String,
) -> (@sqlite.Database, @http.Client, String, String) raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(http_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(sqlite_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_SECRET") is Some(secret) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_CREDENTIAL_JOURNAL")
    is Some(journal_path) else {
    fail("actual credential fixture required")
  }
  let database = @sqlite.load_library(sqlite_path)
    .unwrap()
    .open_database(journal_path + suffix, 65536L)
    .unwrap()
  let client = @http.load_library(http_path)
    .unwrap()
    .create_client(ca, cert, key, 1024L, 2000, 5000)
    .unwrap()
  (database, client, origin, secret)
}

///|
test "Remote retention failure leaves the original claim unresolved and blocks send authorization" {
  let (database, client, origin, secret) = remote_retention_physical_fixture(
    ".retention-failure",
  )
  let scope = credential_test_scope(origin)
  let grant = local_resource_test_remote_grant(scope)
  let mut retained : @credential.RemoteCredentialUse? = None
  let mut calls = 0
  let mut send_authorizations = 0
  let service = install_native_credential_resource_service_with_clock(
    database,
    client,
    [
      {
        resource_origin: origin,
        operation: scope.operation,
        path: "/credential",
        secret_path: secret,
        verb: @http.Get,
        max_request_bytes: 0,
      },
    ],
    value => {
      if value.stage == "send" {
        send_authorizations += 1
      }
      true
    },
    () => 1L,
    retain_remote_use=Some(original_use => {
      calls += 1
      retained = Some(original_use)
      Err(Journal(@sqlite.CapacityExceeded))
    }),
  ).unwrap()
  assert_true(
    call_native_credential_resource(service, grant, "original-use", scope)
    is Err(Journal(@sqlite.CapacityExceeded)),
  )
  let status = query_native_credential_use(
    service, grant, "original-use", scope,
  ).unwrap()
  assert_eq(status.outcome, "claimed")
  assert_eq(status.status, None)
  assert_eq(status.use_cid, @credential.credential_use_cid(retained.unwrap()))
  assert_true(
    call_native_credential_resource(service, grant, "original-use", scope)
    is Err(UseAlreadyClaimed),
  )
  assert_eq(calls, 1)
  assert_eq(send_authorizations, 0)
  assert_true(client.close())
  database.close()
}

///|
test "Remote retention success cannot bypass the final current execution fence" {
  let (database, client, origin, secret) = remote_retention_physical_fixture(
    ".retention-current",
  )
  let scope = credential_test_scope(origin)
  let grant = local_resource_test_remote_grant(scope)
  let mut current = true
  let mut calls = 0
  let service = install_native_credential_resource_service_with_clock(
    database,
    client,
    [
      {
        resource_origin: origin,
        operation: scope.operation,
        path: "/credential",
        secret_path: secret,
        verb: @http.Get,
        max_request_bytes: 0,
      },
    ],
    _ => true,
    () => 1L,
    retain_remote_use=Some(_ => {
      calls += 1
      current = false
      Ok(())
    }),
  ).unwrap()
  assert_true(
    call_native_credential_resource_guarded_request_at_path(
      service,
      grant,
      "original-use",
      scope,
      @http.Get,
      "/credential",
      b"",
      () => current,
    )
    is Err(AccessDenied),
  )
  assert_eq(calls, 1)
  let status = query_native_credential_use(
    service, grant, "original-use", scope,
  ).unwrap()
  assert_eq(status.outcome, "failed")
  assert_eq(status.status, None)
  assert_true(client.close())
  database.close()
}
