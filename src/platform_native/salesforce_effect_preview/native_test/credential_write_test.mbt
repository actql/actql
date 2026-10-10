///|
fn write_grant() -> @credential.RemoteCredentialGrant {
  let envelope = @credential.admit_credential_signature_envelope(
    "actql-remote-credential-grant-signature/0.1",
    "credential-key-a",
    required_env("ACTQL_TEST_NATIVE_SALESFORCE_WRITE_GRANT_CID"),
    required_env("ACTQL_TEST_NATIVE_SALESFORCE_WRITE_GRANT_BODY"),
    required_env("ACTQL_TEST_NATIVE_SALESFORCE_WRITE_SIGNATURE"),
  ).unwrap()
  let signature = @signature.load_library(
    required_env("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY"),
  ).unwrap()
  @resource.admit_signed_native_credential_grant(signature, envelope, [
    {
      issuer_authority: "credential-authority-a",
      key_id: "credential-key-a",
      public_key_pem: required_env(
        "ACTQL_TEST_NATIVE_SALESFORCE_CREDENTIAL_PUBLIC_KEY",
      ),
      admit_new_grants: true,
    },
  ]).unwrap()
}

///|
fn write_operation(
  request : @catalog.SingleWriteRequest,
) -> @resource.NativeCredentialOperation {
  {
    resource_origin: target_scope().resource_origin,
    operation: "salesforce:record:update",
    path: @catalog.single_write_request_path(request),
    secret_path: required_env("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_SECRET"),
    verb: @http.Patch,
    max_request_bytes: 1024,
  }
}

///|
test "Native credential write uses exact checked bytes and does not resend after reconstruction" {
  let (request, _) = target_request("001000000000001")
  let operation = write_operation(request)
  let scope = { ..target_scope(), operation: "salesforce:record:update", }
  let body = @utf8.encode(@catalog.single_write_request_body(request))
  assert_eq(@catalog.single_write_request_method(request), "PATCH")
  let (database, client) = target_physical("write-success")
  let mut authorized = false
  let stages : Array[String] = []
  let installed = [operation]
  let service = @resource.install_native_credential_resource_service(
    database,
    client,
    installed,
    fn(value) {
      stages.push(value.stage)
      if value.stage == "claim" || value.stage == "send" {
        guard value.request is Some(exact) else { return false }
        if exact.verb != @http.Patch ||
          exact.path != operation.path ||
          exact.body != body {
          return false
        }
      }
      authorized
    },
  ).unwrap()
  // Installation is a snapshot; replacing the caller's array does not widen it.
  installed[0] = { ..operation, verb: @http.Post, }
  let grant = write_grant()
  let mut guard_calls = 0
  let send = fn(grant, verb, path, bytes) {
    @resource.call_native_credential_resource_guarded_request_at_path(
      service,
      grant,
      "write-a",
      scope,
      verb,
      path,
      bytes,
      fn() {
        guard_calls = guard_calls + 1
        true
      },
    )
  }
  assert_true(
    send(grant, @http.Post, operation.path, body) is Err(@resource.AccessDenied),
  )
  assert_true(
    send(grant, @http.Patch, operation.path + "/foreign", body)
    is Err(@resource.AccessDenied),
  )
  assert_true(
    send(grant, @http.Patch, operation.path, @utf8.encode("x".repeat(1025)))
    is Err(@resource.AccessDenied),
  )
  assert_eq(stages.length(), 0)
  assert_eq(guard_calls, 0)
  assert_true(
    send(grant, @http.Patch, operation.path, body)
    is Err(@resource.AccessDenied),
  )
  authorized = true
  // Source/target observation authority is not a write grant.
  assert_true(send(target_grant(), @http.Patch, operation.path, body) is Err(_))
  assert_true(
    @resource.call_native_credential_resource_at_path(
      service,
      grant,
      "write-a",
      scope,
      operation.path,
    )
    is Err(@resource.AccessDenied),
  )
  assert_true(
    client.request_bearer_file(
      @http.Patch,
      scope.resource_origin + operation.path,
      [{ name: "authorization", value: "Bearer foreign", }],
      body,
      operation.secret_path,
      2000000000000L,
    )
    is Err(@http.InvalidRequest),
  )
  assert_true(
    client.request_bearer_file(
      @http.Patch,
      scope.resource_origin + operation.path,
      [],
      body,
      operation.secret_path,
      1L,
    )
    is Err(@http.DeadlineExpired),
  )
  let response = send(grant, @http.Patch, operation.path, body).unwrap()
  assert_eq(guard_calls, 2)
  assert_eq(response.status, 200)
  assert_eq(response.body, b"{\"saved\":\"e\\u0301\\r\\n\"}")
  let original = @resource.query_native_credential_use(
    service, grant, "write-a", scope,
  ).unwrap()
  assert_eq(original.outcome, "succeeded")
  assert_eq(original.status, Some(200))
  ignore(client.close())
  database.close_checked().unwrap()
  let (reopened, fresh_client) = target_physical("write-success")
  let fresh = @resource.install_native_credential_resource_service(
    reopened,
    fresh_client,
    [operation],
    _ => true,
  ).unwrap()
  assert_true(
    @resource.call_native_credential_resource_request_at_path(
      fresh,
      grant,
      "write-a",
      scope,
      @http.Patch,
      operation.path,
      body,
    )
    is Err(_),
  )
  let retained = @resource.query_native_credential_use(
    fresh, grant, "write-a", scope,
  ).unwrap()
  assert_eq(retained.use_cid, original.use_cid)
  assert_eq(retained.outcome, "succeeded")
  assert_eq(retained.status, Some(200))
  ignore(fresh_client.close())
  reopened.close_checked().unwrap()
}

///|
test "Native credential write keeps a refused execution fence outside grant consumption" {
  let (request, _) = target_request("001000000000001")
  let operation = write_operation(request)
  let scope = { ..target_scope(), operation: "salesforce:record:update", }
  let body = @utf8.encode(@catalog.single_write_request_body(request))
  let grant = write_grant()
  let (database, client) = target_physical("write-guard-before-claim")
  let service = @resource.install_native_credential_resource_service(
    database,
    client,
    [operation],
    _ => true,
  ).unwrap()
  let mut calls = 0
  for _ in 0..<2 {
    assert_true(
      @resource.call_native_credential_resource_guarded_request_at_path(
        service,
        grant,
        "guard-before-claim",
        scope,
        @http.Patch,
        operation.path,
        body,
        fn() {
          calls = calls + 1
          false
        },
      )
      is Err(@resource.AccessDenied),
    )
  }
  assert_eq(calls, 2)
  assert_true(
    @resource.query_native_credential_use(
      service, grant, "guard-before-claim", scope,
    )
    is Err(@resource.Journal(@sqlite.NotFound)),
  )
  ignore(client.close())
  database.close_checked().unwrap()
}

///|
test "Native credential write rechecks execution fence after Host send authorization" {
  let (request, _) = target_request("001000000000001")
  let operation = write_operation(request)
  let scope = { ..target_scope(), operation: "salesforce:record:update", }
  let body = @utf8.encode(@catalog.single_write_request_body(request))
  let grant = write_grant()
  let (database, client) = target_physical("write-guard-after-host")
  let mut current = true
  let service = @resource.install_native_credential_resource_service(
    database,
    client,
    [operation],
    fn(value) {
      if value.stage == "send" {
        current = false
      }
      true
    },
  ).unwrap()
  let mut calls = 0
  assert_true(
    @resource.call_native_credential_resource_guarded_request_at_path(
      service,
      grant,
      "guard-after-host",
      scope,
      @http.Patch,
      operation.path,
      body,
      fn() {
        calls = calls + 1
        current
      },
    )
    is Err(@resource.AccessDenied),
  )
  assert_eq(calls, 2)
  let retained = @resource.query_native_credential_use(
    service, grant, "guard-after-host", scope,
  ).unwrap()
  assert_eq(retained.outcome, "failed")
  assert_eq(retained.status, None)
  current = true
  // Recovered authority does not make the same already claimed use sendable.
  assert_true(
    @resource.call_native_credential_resource_guarded_request_at_path(
      service,
      grant,
      "guard-after-host",
      scope,
      @http.Patch,
      operation.path,
      body,
      () => current,
    )
    is Err(@resource.UseAlreadyClaimed),
  )
  let confirmed = @resource.query_native_credential_use(
    service, grant, "guard-after-host", scope,
  ).unwrap()
  assert_eq(confirmed.use_cid, retained.use_cid)
  assert_eq(confirmed.outcome, retained.outcome)
  ignore(client.close())
  database.close_checked().unwrap()
}

///|
test "Native credential write rechecks credential revocation after final execution fence" {
  let (request, _) = target_request("001000000000001")
  let operation = write_operation(request)
  let scope = { ..target_scope(), operation: "salesforce:record:update", }
  let body = @utf8.encode(@catalog.single_write_request_body(request))
  let grant = write_grant()
  let (database, client) = target_physical("write-guard-revokes-grant")
  let service = @resource.install_native_credential_resource_service(
    database,
    client,
    [operation],
    _ => true,
  ).unwrap()
  let mut calls = 0
  assert_true(
    @resource.call_native_credential_resource_guarded_request_at_path(
      service,
      grant,
      "guard-revokes-grant",
      scope,
      @http.Patch,
      operation.path,
      body,
      fn() {
        calls = calls + 1
        if calls == 2 {
          @resource.revoke_native_credential_grant(service, grant).unwrap()
        }
        true
      },
    )
    is Err(@resource.Credential(@credential.CredentialGrantInactive)),
  )
  assert_eq(calls, 2)
  let retained = @resource.query_native_credential_use(
    service, grant, "guard-revokes-grant", scope,
  ).unwrap()
  assert_eq(retained.outcome, "failed")
  assert_eq(retained.status, None)
  ignore(client.close())
  database.close_checked().unwrap()
}

///|
test "Native credential write retains unknown after an accepted write loses its response" {
  let (request, _) = target_request("001000000000002")
  let operation = write_operation(request)
  let scope = { ..target_scope(), operation: "salesforce:record:update", }
  let body = @utf8.encode(@catalog.single_write_request_body(request))
  let grant = write_grant()
  let (database, client) = target_physical("write-unknown")
  let service = @resource.install_native_credential_resource_service(
    database,
    client,
    [operation],
    _ => true,
  ).unwrap()
  assert_true(
    @resource.call_native_credential_resource_request_at_path(
      service,
      grant,
      "unknown-a",
      scope,
      @http.Patch,
      operation.path,
      body,
    )
    is Err(@resource.Transport(_)),
  )
  let original = @resource.query_native_credential_use(
    service, grant, "unknown-a", scope,
  ).unwrap()
  assert_eq(original.outcome, "unknown")
  assert_eq(original.status, None)
  ignore(client.close())
  database.close_checked().unwrap()
  let (reopened, fresh_client) = target_physical("write-unknown")
  let fresh = @resource.install_native_credential_resource_service(
    reopened,
    fresh_client,
    [operation],
    _ => true,
  ).unwrap()
  assert_true(
    @resource.call_native_credential_resource_request_at_path(
      fresh,
      grant,
      "unknown-a",
      scope,
      @http.Patch,
      operation.path,
      body,
    )
    is Err(_),
  )
  let retained = @resource.query_native_credential_use(
    fresh, grant, "unknown-a", scope,
  ).unwrap()
  assert_eq(retained.use_cid, original.use_cid)
  assert_eq(retained.outcome, "unknown")
  ignore(fresh_client.close())
  reopened.close_checked().unwrap()
}

///|
test "Native credential write rechecks authorization after its durable claim" {
  let (request, _) = target_request("001000000000001")
  let operation = write_operation(request)
  let scope = { ..target_scope(), operation: "salesforce:record:update", }
  let body = @utf8.encode(@catalog.single_write_request_body(request))
  let grant = write_grant()
  let (database, client) = target_physical("write-revoked")
  let mut holder : @resource.NativeCredentialResourceService? = None
  let service = @resource.install_native_credential_resource_service(
    database,
    client,
    [operation],
    fn(value) {
      if value.stage == "send" {
        // The durable revocation happens during the authorization callback.
        // The Owner must inspect it again before the actual HTTP request.
        ignore(@resource.revoke_native_credential_grant(holder.unwrap(), grant))
      }
      true
    },
  ).unwrap()
  holder = Some(service)
  assert_true(
    @resource.call_native_credential_resource_request_at_path(
      service,
      grant,
      "revoked-a",
      scope,
      @http.Patch,
      operation.path,
      body,
    )
    is Err(@resource.Credential(@credential.CredentialGrantInactive)),
  )
  let retained = @resource.query_native_credential_use(
    service, grant, "revoked-a", scope,
  ).unwrap()
  assert_eq(retained.outcome, "failed")
  assert_eq(retained.status, None)
  assert_true(
    @resource.call_native_credential_resource_request_at_path(
      service,
      grant,
      "revoked-a",
      scope,
      @http.Patch,
      operation.path,
      body,
    )
    is Err(@resource.Credential(@credential.CredentialGrantInactive)),
  )
  ignore(client.close())
  database.close_checked().unwrap()
}

///|
test "Native credential write preserves the raw Provider refusal without resending it" {
  let (request, _) = target_request("001000000000003")
  let operation = write_operation(request)
  let scope = { ..target_scope(), operation: "salesforce:record:update", }
  let body = @utf8.encode(@catalog.single_write_request_body(request))
  let grant = write_grant()
  let (database, client) = target_physical("write-refused")
  let service = @resource.install_native_credential_resource_service(
    database,
    client,
    [operation],
    _ => true,
  ).unwrap()
  let response = @resource.call_native_credential_resource_request_at_path(
    service,
    grant,
    "refused-a",
    scope,
    @http.Patch,
    operation.path,
    body,
  ).unwrap()
  assert_eq(response.status, 409)
  assert_eq(response.body, b"{\"refused\":\"e\\u0301\\r\\n\"}")
  let original = @resource.query_native_credential_use(
    service, grant, "refused-a", scope,
  ).unwrap()
  assert_eq(original.outcome, "failed")
  assert_eq(original.status, Some(409))
  ignore(client.close())
  database.close_checked().unwrap()
  let (reopened, fresh_client) = target_physical("write-refused")
  let fresh = @resource.install_native_credential_resource_service(
    reopened,
    fresh_client,
    [operation],
    _ => true,
  ).unwrap()
  assert_true(
    @resource.call_native_credential_resource_request_at_path(
      fresh,
      grant,
      "refused-a",
      scope,
      @http.Patch,
      operation.path,
      body,
    )
    is Err(_),
  )
  let retained = @resource.query_native_credential_use(
    fresh, grant, "refused-a", scope,
  ).unwrap()
  assert_eq(retained.use_cid, original.use_cid)
  assert_eq(retained.status, Some(409))
  ignore(fresh_client.close())
  reopened.close_checked().unwrap()
}
