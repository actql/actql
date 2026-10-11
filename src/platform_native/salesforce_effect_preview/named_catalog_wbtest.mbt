///|
fn named_catalog_test_binding() -> @catalog.CatalogObservationBinding {
  {
    namespace_id: "namespace-a",
    principal: "principal-a",
    environment: "test",
    connection_revision: "connection-a",
    org_id: "00D000000000001EAA",
    site_key: "site-a",
    site_generation: 4,
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: "https://provider.example",
    run_invocation_cid: "sha256:" + "a".repeat(64),
    dispatch_request_cid: "sha256:" + "b".repeat(64),
    sync_occurrence: "original-catalog-read",
  }
}

///|
fn named_catalog_test_scope() -> @resource.NativeCredentialScope {
  let binding = named_catalog_test_binding()
  {
    namespace_id: binding.namespace_id,
    principal: binding.principal,
    environment: binding.environment,
    site_key: binding.site_key,
    site_generation: binding.site_generation,
    connector_registration: binding.connector_registration,
    connector_revision: binding.connector_revision,
    resource_origin: binding.resource_origin,
    run_invocation_cid: binding.run_invocation_cid,
    dispatch_request_cid: binding.dispatch_request_cid,
    operation: "salesforce:catalog:describe",
    runtime_bundle_cid: "sha256:" + "c".repeat(64),
    task_attempt: 1,
  }
}

///|
test "named Catalog dispatch validates each independent Scope field before selecting a physical path" {
  let scope = named_catalog_test_scope()
  let binding = named_catalog_test_binding()
  assert_eq(
    native_named_catalog_path(
      scope,
      binding,
      binding.org_id,
      "v66.0",
      "ActQL_Test_Record__c",
    ).unwrap(),
    "/services/data/v66.0/sobjects/ActQL_Test_Record__c/describe",
  )
  for
    foreign in [
      { ..scope, namespace_id: "foreign", },
      { ..scope, principal: "foreign", },
      { ..scope, environment: "foreign", },
      { ..scope, site_key: "foreign", },
      { ..scope, site_generation: 5, },
      { ..scope, connector_registration: "foreign", },
      { ..scope, connector_revision: "foreign", },
      { ..scope, resource_origin: "https://foreign.example", },
      { ..scope, run_invocation_cid: "sha256:" + "d".repeat(64), },
      { ..scope, dispatch_request_cid: "sha256:" + "d".repeat(64), },
      { ..scope, operation: "salesforce:record:apply", },
    ] {
    assert_true(
      native_named_catalog_path(
        foreign,
        binding,
        binding.org_id,
        "v66.0",
        "ActQL_Test_Record__c",
      )
      is Err(CatalogScopeMismatch),
    )
  }
  assert_true(
    native_named_catalog_path(
      scope, binding, "foreign-org", "v66.0", "ActQL_Test_Record__c",
    )
    is Err(CatalogScopeMismatch),
  )
}

///|
test "named Catalog path refuses malformed version and Resource before credential use" {
  let scope = named_catalog_test_scope()
  let binding = named_catalog_test_binding()
  for version in ["", "v0.0", "v66", "v66.", "v66..0", "v66.0/../", "v66.0?x"] {
    assert_true(
      native_named_catalog_path(
        scope,
        binding,
        binding.org_id,
        version,
        "ActQL_Test_Record__c",
      )
      is Err(InvalidCatalogConfiguration),
    )
  }
  for
    resource in [
      "", "../Account", "Account/describe", "Account?x", "Account\u{0}",
    ] {
    assert_true(
      native_named_catalog_path(
        scope,
        binding,
        binding.org_id,
        "v66.0",
        resource,
      )
      is Err(InvalidCatalogConfiguration),
    )
  }
}

///|
fn named_catalog_test_limits() -> @catalog.DescribeLimits {
  {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 2,
    max_name_units: 100,
  }
}

///|
test "named Catalog response projects exact use and bytes and restores without a listing" {
  let binding = named_catalog_test_binding()
  let name = "ActQL_Test_Record__c"
  let body = @utf8.encode(
    (
      #|{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"fields":[{"name":"Name","type":"string","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true}]}
    ),
  )
  let response : @resource.NativeCredentialResponse = {
    use_cid: "sha256:" + "e".repeat(64),
    status: 200,
    body,
  }
  let observation = native_named_catalog_response(
    binding,
    name,
    named_catalog_test_limits(),
    8192,
    response,
  ).unwrap()
  let wire = @catalog.catalog_observation_json(observation)
  assert_true(wire.contains(response.use_cid))
  assert_true(wire.contains(@catalog.catalog_response_sha256(body)))
  let restored = @catalog.recover_named_catalog_observation(
    wire,
    [name],
    [Some(body)],
    [1],
    binding,
    [Some(response.use_cid)],
    [Some(@catalog.catalog_response_sha256(body))],
    named_catalog_test_limits(),
    8192,
  ).unwrap()
  assert_eq(@catalog.catalog_observation_json(restored), wire)
  assert_true(wire.contains("\"truncated\":true"))
  assert_true(wire.contains("\"listing_use_cid\":null"))
  assert_true(wire.contains("\"listing_response_sha256\":null"))
}

///|
test "failed metadata retains response evidence and cannot become an available Catalog" {
  let binding = named_catalog_test_binding()
  let response : @resource.NativeCredentialResponse = {
    use_cid: "sha256:" + "e".repeat(64),
    status: 403,
    body: @utf8.encode("denied"),
  }
  match
    native_named_catalog_response(
      binding,
      "Account",
      named_catalog_test_limits(),
      8192,
      response,
    ) {
    Err(MetadataReadUnavailable(saved)) => {
      assert_eq(saved.use_cid, response.use_cid)
      assert_eq(saved.body, response.body)
      assert_eq(saved.status, 403)
    }
    _ => fail("Unavailable metadata must retain its exact physical response")
  }
  let malformed = { ..response, status: 200, body: @utf8.encode("{}"), }
  match
    native_named_catalog_response(
      binding,
      "Account",
      named_catalog_test_limits(),
      8192,
      malformed,
    ) {
    Err(CatalogSyncFailure(_, saved)) => {
      assert_eq(saved.use_cid, response.use_cid)
      assert_eq(saved.body, malformed.body)
    }
    _ => fail("Invalid metadata must not issue an available Catalog")
  }
}
