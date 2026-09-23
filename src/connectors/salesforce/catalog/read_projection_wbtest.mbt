///|
fn read_test_observation() -> (CatalogObservation, CatalogObservationBinding) {
  let sync = observation_test_sync()
  finish_catalog_sync(sync).unwrap()
  let binding = observation_test_binding()
  let response_digest = match catalog_sync_outcome(sync, "Account") {
    Some(Described(resource)) => resource.response_sha256
    _ => abort("expected described Account")
  }
  let observation = prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [Some(response_digest)],
    4096,
  ).unwrap()
  (observation, binding)
}

///|
test "read projection uses only the supplied complete resource view" {
  let (observation, binding) = read_test_observation()
  let plan = prepare_read_projection(
    observation,
    binding,
    "Account",
    ["Id"],
    22,
  ).unwrap()
  assert_eq(read_projection_soql(plan), "SELECT Id FROM Account")
  assert_eq(
    read_projection_observation(plan),
    catalog_observation_identity(observation),
  )
  assert_eq(read_projection_fields(plan), ["Id"])
  assert_true(
    read_projection_matches_site_scope(
      plan,
      binding.tenant,
      binding.principal,
      binding.environment,
      binding.site_key,
      binding.site_generation,
      binding.connector_registration,
      binding.connector_revision,
      binding.resource_origin,
      binding.run_invocation_cid,
      binding.dispatch_request_cid,
    ),
  )
  assert_false(
    read_projection_matches_site_scope(
      plan,
      binding.tenant,
      binding.principal,
      binding.environment,
      binding.site_key,
      binding.site_generation + 1,
      binding.connector_registration,
      binding.connector_revision,
      binding.resource_origin,
      binding.run_invocation_cid,
      binding.dispatch_request_cid,
    ),
  )
  assert_true(
    prepare_read_projection(observation, binding, "Account", ["Id"], 21)
    is Err(QueryLimit),
  )
  assert_true(
    prepare_read_projection(observation, binding, "Account", [], 100)
    is Err(EmptyProjection),
  )
}

///|
test "read projection preserves missing-field and foreign-binding diagnostics" {
  let (observation, binding) = read_test_observation()
  assert_true(
    prepare_read_projection(
      observation,
      binding,
      "Account",
      ["Hidden_Field__c"],
      100,
    )
    is Err(Requirement(FieldUnconfirmed("Hidden_Field__c"))),
  )
  assert_true(
    prepare_read_projection(
      observation,
      { ..binding, site_generation: 5, },
      "Account",
      ["Id"],
      100,
    )
    is Err(Observation(ForeignBinding)),
  )
  assert_true(
    prepare_read_projection(observation, binding, "Contact", ["Id"], 100)
    is Err(Observation(Resource(NotVisible))),
  )
}
