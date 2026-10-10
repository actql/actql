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
