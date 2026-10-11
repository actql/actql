///|
test "review Catalog retains original Run and dispatch even with the same Resource metadata" {
  let binding = named_catalog_test_binding()
  let response : @resource.NativeCredentialResponse = {
    use_cid: "sha256:" + "d".repeat(64),
    status: 200,
    body: @utf8.encode(
      "{\"name\":\"ActQL_Test_Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true,\"fields\":[{\"name\":\"Count__c\",\"type\":\"int\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}]}",
    ),
  }
  let observe = binding => {
    native_named_catalog_response(
      binding,
      "ActQL_Test_Record__c",
      {
        max_bytes: 4096,
        max_nodes: 100,
        max_depth: 16,
        max_fields: 2,
        max_name_units: 100,
      },
      8192,
      response,
    ).unwrap()
  }
  let matches = catalog => {
    native_review_catalog_matches_original(
      catalog,
      binding.site_key,
      binding.site_generation.to_string(),
      binding.run_invocation_cid,
      binding.dispatch_request_cid,
    )
  }
  assert_true(matches(observe(binding)))
  // Each candidate is a normally admitted named Catalog; neither matching
  // metadata nor a self-consistent Catalog CID supplies the original scope.
  for
    foreign in [
      { ..binding, site_key: "foreign-site", },
      { ..binding, site_generation: 5, },
      { ..binding, run_invocation_cid: "sha256:" + "e".repeat(64), },
      { ..binding, dispatch_request_cid: "sha256:" + "e".repeat(64), },
    ] {
    let candidate = observe(foreign)
    assert_true(
      @catalog.catalog_observation_matches_binding(candidate, foreign),
    )
    assert_false(matches(candidate))
  }
}

///|
test "Resident Catalog creation retains the exact original Site origin" {
  let binding = named_catalog_test_binding()
  assert_eq(
    native_resident_catalog_create_origin(@catalog.SiteCatalog(binding)).unwrap(),
    "https://provider.example",
  )
}

///|
test "Direct Local Catalog cannot supply Resident review or create custody" {
  let site = named_catalog_test_binding()
  let binding : @catalog.LocalCatalogObservationBinding = {
    account_configuration_cid: local_target_test_cid("1"),
    account_id: "account-a",
    authority_scope_cid: local_target_test_cid("2"),
    client_request_intent_cid: local_target_test_cid("3"),
    client_request_scope_cid: local_target_test_cid("4"),
    connection_revision: site.connection_revision,
    connector_registration: site.connector_registration,
    connector_revision: site.connector_revision,
    environment: site.environment,
    host_adoption_cid: local_target_test_cid("5"),
    namespace_id: site.namespace_id,
    org_id: site.org_id,
    principal: site.principal,
    resource_origin: site.resource_origin,
    run_invocation_cid: site.run_invocation_cid,
    sync_occurrence: site.sync_occurrence,
  }
  let local = @catalog.DirectLocalCatalog(binding)
  assert_false(
    native_review_catalog_binding_matches_original(
      local,
      site.site_key,
      site.site_generation.to_string(),
      site.run_invocation_cid,
      site.dispatch_request_cid,
    ),
  )
  assert_true(
    native_resident_catalog_create_origin(local) is Err(ForeignRequest),
  )
}
