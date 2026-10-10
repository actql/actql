///|
fn required_env(name : String) -> String {
  @env.get_env_var(name).unwrap()
}

///|
fn target_scope() -> @resource.NativeCredentialScope {
  {
    principal: "principal-a",
    namespace_id: "namespace-a",
    environment: "test",
    site_key: "site-a",
    site_generation: 4,
    runtime_bundle_cid: "sha256:" + "a".repeat(64),
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: required_env("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_URL"),
    operation: "salesforce:record:observe",
    run_invocation_cid: "sha256:" + "b".repeat(64),
    task_attempt: 3,
    dispatch_request_cid: "sha256:" + "c".repeat(64),
  }
}

///|
fn target_request(
  record : String,
) -> (@catalog.SingleWriteRequest, @catalog.CatalogObservation) {
  let scope = target_scope()
  let binding : @catalog.CatalogObservationBinding = {
    namespace_id: scope.namespace_id,
    principal: scope.principal,
    environment: scope.environment,
    connection_revision: "connection-a",
    org_id: "00D000000000001EAA",
    site_key: scope.site_key,
    site_generation: scope.site_generation,
    connector_registration: scope.connector_registration,
    connector_revision: scope.connector_revision,
    resource_origin: scope.resource_origin,
    run_invocation_cid: scope.run_invocation_cid,
    dispatch_request_cid: scope.dispatch_request_cid,
    sync_occurrence: "sync-a",
  }
  let listing = @catalog.project_resource_listing(
    @utf8.encode(
      (
        #|{"sobjects":[{"name":"ActQL_Test_Record__c","queryable":true,"updateable":true}]}
      ),
    ),
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 1,
      max_selected: 1,
      max_name_units: 100,
    },
  ).unwrap()
  let description = @utf8.encode(
    (
      #|{"name":"ActQL_Test_Record__c","queryable":true,"updateable":true,"fields":[{"name":"Optional_Value__c","type":"string","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true}]}
    ),
  )
  let sync = @catalog.begin_catalog_sync(listing)
  @catalog.catalog_sync_describe(sync, "ActQL_Test_Record__c", description, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 2,
    max_name_units: 100,
  }).unwrap()
  @catalog.finish_catalog_sync(sync).unwrap()
  let observation = @catalog.prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "d".repeat(64),
    [Some("sha256:" + "e".repeat(64))],
    [Some(@sha.hex(description))],
    8192,
  ).unwrap()
  let projection = @catalog.prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    @catalog.WriteUpdateById,
    ["Optional_Value__c"],
    1,
  ).unwrap()
  let body = @catalog.prepare_write_body(
    projection,
    @utf8.encode("{\"Optional_Value__c\":\"new\"}"),
    { max_bytes: 1024, max_nodes: 8, max_depth: 2, },
  ).unwrap()
  (
    @catalog.prepare_single_write_request(
      body,
      "v66.0",
      @catalog.RecordId(record),
      { max_path_bytes: 1024, max_target_bytes: 128, max_body_bytes: 1024, },
    ).unwrap(),
    observation,
  )
}

///|
fn target_grant() -> @credential.RemoteCredentialGrant {
  let envelope = @credential.admit_credential_signature_envelope(
    "actql-remote-credential-grant-signature/0.1",
    "credential-key-a",
    required_env("ACTQL_TEST_NATIVE_SALESFORCE_CREDENTIAL_GRANT_CID"),
    required_env("ACTQL_TEST_NATIVE_SALESFORCE_CREDENTIAL_GRANT_BODY"),
    required_env("ACTQL_TEST_NATIVE_SALESFORCE_CREDENTIAL_SIGNATURE"),
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
fn target_physical(name : String) -> (@sqlite.Database, @http.Client) {
  let sqlite = @sqlite.load_library(
    required_env("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"),
  ).unwrap()
  let database = sqlite
    .open_database(
      required_env("ACTQL_TEST_NATIVE_SALESFORCE_TARGET_ROOT") +
      "/" +
      name +
      ".sqlite",
      65536L,
    )
    .unwrap()
  let http = @http.load_library(
    required_env("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_LIBRARY"),
  ).unwrap()
  let client = http
    .create_authenticated_client(
      required_env("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_CA"),
      @http.Bearer(required_env("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_SECRET")),
      1024L,
      2000,
      5000,
    )
    .unwrap()
  (database, client)
}

///|
fn target_service(
  database : @sqlite.Database,
  client : @http.Client,
  path : String,
  authorize : (@resource.NativeCredentialAuthorization) -> Bool,
) -> @resource.NativeCredentialResourceService {
  @resource.install_native_credential_resource_service(
    database,
    client,
    [
      {
        resource_origin: target_scope().resource_origin,
        operation: "salesforce:record:observe",
        path,
        secret_path: required_env("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_SECRET"),
      },
    ],
    authorize,
  ).unwrap()
}

///|
fn target_limits() -> @catalog.TargetObservationLimits {
  { max_bytes: 1024, max_nodes: 32, max_depth: 5, max_identity_bytes: 1024, }
}

///|
test "Native Effect target read yields Provider facts without applying a write" {
  let (request, catalog) = target_request("001000000000001")
  let (database, client) = target_physical("normal")
  let stages : Array[String] = []
  let service = target_service(
    database,
    client,
    @catalog.single_write_request_path(request),
    x => {
      stages.push(x.stage)
      true
    },
  )
  let grant = target_grant()
  let (use_cid, observation, row) = @preview.observe_native_salesforce_effect_target(
    service,
    grant,
    "target-a",
    target_scope(),
    "00D000000000001EAA",
    request,
    catalog,
    target_limits(),
  ).unwrap()
  assert_eq(stages, ["claim", "send"])
  assert_true(use_cid.has_prefix("sha256:"))
  assert_eq(@catalog.target_preview_row_target_wire(row), "\"001000000000001\"")
  assert_eq(
    @catalog.target_preview_row_before_wire(row),
    "{\"Optional_Value__c\":\"e\u{0301}\\r\\n\"}",
  )
  assert_eq(
    @catalog.target_preview_row_after_wire(row),
    "{\"Optional_Value__c\":\"new\"}",
  )
  assert_eq(
    @catalog.target_preview_row_guard_cid(row),
    @catalog.target_observation_version_cid(observation),
  )
  assert_eq(
    @resource.query_native_credential_use(
      service,
      grant,
      "target-a",
      target_scope(),
    ).unwrap().outcome,
    "succeeded",
  )
  assert_true(
    @preview.observe_native_salesforce_effect_target(
      service,
      grant,
      "target-a",
      target_scope(),
      "00D000000000001EAA",
      request,
      catalog,
      target_limits(),
    )
    is Err(@preview.Credential(_)),
  )
  assert_eq(
    @resource.query_native_credential_use(
      service,
      grant,
      "target-a",
      target_scope(),
    ).unwrap().outcome,
    "succeeded",
  )
  assert_true(client.close())
  database.close()
}

///|
test "Native Effect mismatched scope org path and limits consume no credential use" {
  let (request, catalog) = target_request("001000000000001")
  let (database, client) = target_physical("refusal")
  let mut calls = 0
  let authorize = (_ : @resource.NativeCredentialAuthorization) => {
    calls += 1
    true
  }
  let service = target_service(database, client, "/wrong-target", authorize)
  let grant = target_grant()
  assert_true(
    @preview.observe_native_salesforce_effect_target(
      service,
      grant,
      "never-claimed",
      { ..target_scope(), site_generation: 5, },
      "00D000000000001EAA",
      request,
      catalog,
      target_limits(),
    )
    is Err(@preview.ForeignScope),
  )
  assert_true(
    @preview.observe_native_salesforce_effect_target(
      service,
      grant,
      "never-claimed",
      target_scope(),
      "00D000000000002EAA",
      request,
      catalog,
      target_limits(),
    )
    is Err(@preview.ForeignScope),
  )
  assert_true(
    @preview.observe_native_salesforce_effect_target(
      service,
      grant,
      "never-claimed",
      { ..target_scope(), operation: "records:read", },
      "00D000000000001EAA",
      request,
      catalog,
      target_limits(),
    )
    is Err(@preview.ForeignScope),
  )
  assert_true(
    @preview.observe_native_salesforce_effect_target(
      service,
      grant,
      "never-claimed",
      target_scope(),
      "00D000000000001EAA",
      request,
      catalog,
      { ..target_limits(), max_bytes: 0, },
    )
    is Err(@preview.InvalidLimits),
  )
  assert_true(
    @preview.observe_native_salesforce_effect_target(
      service,
      grant,
      "never-claimed",
      target_scope(),
      "00D000000000001EAA",
      request,
      catalog,
      target_limits(),
    )
    is Err(@preview.Credential(@resource.AccessDenied)),
  )
  assert_eq(calls, 0)
  let allowed = target_service(
    database,
    client,
    @catalog.single_write_request_path(request),
    authorize,
  )
  ignore(
    @preview.observe_native_salesforce_effect_target(
      allowed,
      grant,
      "never-claimed",
      target_scope(),
      "00D000000000001EAA",
      request,
      catalog,
      target_limits(),
    ).unwrap(),
  )
  assert_eq(calls, 2)
  assert_true(client.close())
  database.close()
}

///|
test "Native Effect permission revoked before target send records failure and reads nothing" {
  let (request, catalog) = target_request("001000000000001")
  let (database, client) = target_physical("authorization")
  let service = target_service(
    database,
    client,
    @catalog.single_write_request_path(request),
    x => x.stage != "send",
  )
  let grant = target_grant()
  assert_true(
    @preview.observe_native_salesforce_effect_target(
      service,
      grant,
      "denied-before-send",
      target_scope(),
      "00D000000000001EAA",
      request,
      catalog,
      target_limits(),
    )
    is Err(@preview.Credential(@resource.AccessDenied)),
  )
  assert_eq(
    @resource.query_native_credential_use(
      service,
      grant,
      "denied-before-send",
      target_scope(),
    ).unwrap().outcome,
    "failed",
  )
  assert_true(client.close())
  database.close()
}

///|
test "Native Effect foreign physical target yields no Preview guard or retry" {
  let (request, catalog) = target_request("001000000000002")
  let (database, client) = target_physical("foreign-response")
  let service = target_service(
    database,
    client,
    @catalog.single_write_request_path(request),
    _ => true,
  )
  let grant = target_grant()
  assert_true(
    @preview.observe_native_salesforce_effect_target(
      service,
      grant,
      "wrong-record",
      target_scope(),
      "00D000000000001EAA",
      request,
      catalog,
      target_limits(),
    )
    is Err(@preview.Observation(@catalog.ForeignTarget)),
  )
  assert_true(
    @preview.observe_native_salesforce_effect_target(
      service,
      grant,
      "wrong-record",
      target_scope(),
      "00D000000000001EAA",
      request,
      catalog,
      target_limits(),
    )
    is Err(@preview.Credential(_)),
  )
  assert_true(client.close())
  database.close()
}

///|
test "Native Effect grant revoked during claim cannot reach target I/O" {
  let (request, catalog) = target_request("001000000000001")
  let (database, client) = target_physical("grant-revocation")
  let grant = target_grant()
  let mut owner : @resource.NativeCredentialResourceService? = None
  let service = target_service(
    database,
    client,
    @catalog.single_write_request_path(request),
    fn(value) {
      if value.stage == "claim" {
        @resource.revoke_native_credential_grant(owner.unwrap(), grant).unwrap()
      }
      true
    },
  )
  owner = Some(service)
  assert_true(
    @preview.observe_native_salesforce_effect_target(
      service,
      grant,
      "revoked-during-claim",
      target_scope(),
      "00D000000000001EAA",
      request,
      catalog,
      target_limits(),
    )
    is Err(
      Credential(@resource.Credential(@credential.CredentialGrantInactive))
    ),
  )
  assert_eq(
    @resource.query_native_credential_use(
      service,
      grant,
      "revoked-during-claim",
      target_scope(),
    ).unwrap().outcome,
    "failed",
  )
  assert_true(client.close())
  database.close()
}

///|
test "Existing Native credential call also rejects revocation during claim" {
  let (request, _) = target_request("001000000000001")
  let (database, client) = target_physical("original-api-revocation")
  let grant = target_grant()
  let mut owner : @resource.NativeCredentialResourceService? = None
  let service = target_service(
    database,
    client,
    @catalog.single_write_request_path(request),
    fn(value) {
      if value.stage == "claim" {
        @resource.revoke_native_credential_grant(owner.unwrap(), grant).unwrap()
      }
      true
    },
  )
  owner = Some(service)
  assert_true(
    @resource.call_native_credential_resource(
      service,
      grant,
      "revoked-during-claim",
      target_scope(),
    )
    is Err(@resource.Credential(@credential.CredentialGrantInactive)),
  )
  assert_eq(
    @resource.query_native_credential_use(
      service,
      grant,
      "revoked-during-claim",
      target_scope(),
    ).unwrap().outcome,
    "failed",
  )
  assert_true(client.close())
  database.close()
}
