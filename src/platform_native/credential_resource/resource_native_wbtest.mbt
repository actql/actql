///|
fn credential_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn credential_test_scope(origin : String) -> NativeCredentialScope {
  {
    principal: "principal-a",
    tenant: "tenant-a",
    environment: "test",
    site_key: "site-a",
    site_generation: 2,
    runtime_bundle_cid: credential_test_cid("a"),
    connector_registration: "http-source",
    connector_revision: "http-source/1",
    resource_origin: origin,
    operation: "records:read",
    run_invocation_cid: credential_test_cid("b"),
    task_attempt: 3,
    dispatch_request_cid: credential_test_cid("c"),
  }
}

///|
test "native credential resource consumes one durable scoped use" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(http_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(sqlite_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(crypto_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_SECRET") is Some(secret) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_CREDENTIAL_GRANT_BODY")
    is Some(grant_body) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_CREDENTIAL_GRANT_CID")
    is Some(grant_cid) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_CREDENTIAL_KEY_ID") is Some(key_id) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_CREDENTIAL_SIGNATURE")
    is Some(signature) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_CREDENTIAL_PUBLIC_KEY")
    is Some(public_key) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_CREDENTIAL_JOURNAL")
    is Some(journal_path) else {
    return
  }
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let database = sqlite.open_database(journal_path, 65536L).unwrap()
  let http = @http.load_library(http_path).unwrap()
  let client = http.create_client(ca, cert, key, 1024L, 2000, 5000).unwrap()
  let stages : Array[String] = []
  let service = install_native_credential_resource_service(
    database,
    client,
    [
      {
        resource_origin: origin,
        operation: "records:read",
        path: "/credential",
        secret_path: secret,
      },
    ],
    fn(value) {
      stages.push(value.stage)
      true
    },
  ).unwrap()
  let scope = credential_test_scope(origin)
  let envelope = @credential.admit_credential_signature_envelope(
    "actql-remote-credential-grant-signature/0.1", key_id, grant_cid, grant_body,
    signature,
  ).unwrap()
  let signature_library = @signature.load_library(crypto_path).unwrap()
  let grant = admit_signed_native_credential_grant(
    signature_library,
    envelope,
    [
      {
        issuer_authority: "credential-authority-a",
        key_id,
        public_key_pem: public_key,
        admit_new_grants: true,
      },
    ],
  ).unwrap()
  let altered_signature = (if signature.has_prefix("A") { "B" } else { "A" }) +
    signature.unsafe_substring(start=1, end=signature.length())
  let altered_envelope = @credential.admit_credential_signature_envelope(
    "actql-remote-credential-grant-signature/0.1", key_id, grant_cid, grant_body,
    altered_signature,
  ).unwrap()
  assert_true(
    admit_signed_native_credential_grant(signature_library, altered_envelope, [
      {
        issuer_authority: "credential-authority-a",
        key_id,
        public_key_pem: public_key,
        admit_new_grants: true,
      },
    ])
    is Err(Credential(@credential.InvalidCredentialSignature)),
  )
  let response = call_native_credential_resource(
    service, grant, "use-a", 1999999999999L, scope,
  ).unwrap()
  assert_eq(response.status, 200)
  assert_eq(response.body, b"{\"authorized\":true}")
  let status = query_native_credential_use(service, grant, "use-a", scope).unwrap()
  assert_eq(status.use_cid, response.use_cid)
  assert_eq(status.outcome, "succeeded")
  assert_eq(status.status, Some(200))
  assert_eq(stages, ["claim", "send", "query", "return"])
  revoke_native_credential_grant(service, grant).unwrap()
  guard call_native_credential_resource(
      service, grant, "revoked", 1999999999999L, scope,
    )
    is Err(Credential(@credential.CredentialGrantInactive)) else {
    fail("revoked credential grant started another resource call")
  }
  guard call_native_credential_resource(
      service, grant, "use-a", 1999999999999L, scope,
    )
    is Err(UseAlreadyClaimed) else {
    fail("exact credential retry started another resource call")
  }
  guard call_native_credential_resource(
      service, grant, "use-b", 1999999999999L, scope,
    )
    is Err(Journal(@sqlite.CapacityExceeded)) else {
    fail("credential use ceiling was not durable")
  }
  let expired_grant = @credential.prepare_grant(
    "credential-authority-a",
    scope.principal,
    scope.tenant,
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
    credential_test_cid("d"),
    10L,
    1,
  ).unwrap()
  let expired_scope : NativeCredentialScope = {
    ..scope,
    dispatch_request_cid: credential_test_cid("d"),
  }
  guard call_native_credential_resource(
      service, expired_grant, "expired", 10L, expired_scope,
    )
    is Err(Credential(@credential.CredentialGrantInactive)) else {
    fail("expired credential grant consumed a durable use")
  }
  guard query_native_credential_use(
      service, expired_grant, "expired", expired_scope,
    )
    is Err(Journal(@sqlite.NotFound)) else {
    fail("expired credential use was durably claimed")
  }
  let foreign : NativeCredentialScope = { ..scope, operation: "records:write", }
  guard call_native_credential_resource(
      service, grant, "foreign", 1999999999999L, foreign,
    )
    is Err(Credential(@credential.CredentialGrantInactive)) else {
    fail("foreign credential operation was accepted")
  }
  assert_true(client.close())
  database.close()
  let reopened_database = sqlite.open_database(journal_path, 65536L).unwrap()
  let reopened_client = http
    .create_client(ca, cert, key, 1024L, 2000, 5000)
    .unwrap()
  let reopened = install_native_credential_resource_service(
    reopened_database,
    reopened_client,
    [
      {
        resource_origin: origin,
        operation: "records:read",
        path: "/credential",
        secret_path: secret,
      },
    ],
    fn(_) { true },
  ).unwrap()
  let recovered = query_native_credential_use(reopened, grant, "use-a", scope).unwrap()
  assert_eq(recovered.use_cid, response.use_cid)
  assert_eq(recovered.outcome, "succeeded")
  guard call_native_credential_resource(
      reopened, grant, "restart-revoked", 1999999999999L, scope,
    )
    is Err(Credential(@credential.CredentialGrantInactive)) else {
    fail("restart lost durable credential revocation")
  }
  ignore(reopened_client.close())
  reopened_database.close()
}
