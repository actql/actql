///|
fn observation_test_binding() -> CatalogObservationBinding {
  {
    tenant: "tenant-a",
    principal: "principal-a",
    environment: "test",
    connection_revision: "connection-revision-a",
    site_key: "site-a",
    site_generation: 4,
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: "https://example.invalid",
    run_invocation_cid: "sha256:" + "a".repeat(64),
    dispatch_request_cid: "sha256:" + "b".repeat(64),
    sync_occurrence: "sync-a",
  }
}

///|
fn observation_test_sync() -> CatalogSync {
  let listing = project_resource_listing(
    @utf8.encode(
      (
        #|{"sobjects":[{"name":"Account","queryable":true}]}
      ),
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = begin_catalog_sync(listing)
  catalog_sync_describe(
    sync,
    "Account",
    @utf8.encode(
      (
        #|{"name":"Account","queryable":true,"fields":[{"name":"Id","type":"id","nillable":false}]}
      ),
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_fields: 10,
      max_name_units: 100,
    },
  ).unwrap()
  sync
}

///|
test "catalog observation binds exact connection, Site and use evidence" {
  let sync = observation_test_sync()
  let binding = observation_test_binding()
  let list_use = "sha256:" + "c".repeat(64)
  let describe_use = "sha256:" + "d".repeat(64)
  let response_digest = match catalog_sync_outcome(sync, "Account") {
    Some(Described(resource)) => resource.response_sha256
    _ => abort("expected described Account")
  }
  assert_true(
    prepare_catalog_observation(
      sync,
      binding,
      list_use,
      [Some(describe_use)],
      [Some(response_digest)],
      4096,
    )
    is Err(IncompleteSync),
  )
  finish_catalog_sync(sync).unwrap()
  let observation = prepare_catalog_observation(
    sync,
    binding,
    list_use,
    [Some(describe_use)],
    [Some(response_digest)],
    4096,
  ).unwrap()
  let body = catalog_observation_json(observation)
  assert_true(
    body.contains("\"connection_revision\":\"connection-revision-a\""),
  )
  assert_true(body.contains("\"outcome\":\"described\""))
  assert_eq(
    catalog_observation_identity(observation),
    "sha256:" + @sha.hex(@utf8.encode(body)),
  )
  let next_connection = prepare_catalog_observation(
    sync,
    { ..binding, connection_revision: "connection-revision-b", },
    list_use,
    [Some(describe_use)],
    [Some(response_digest)],
    4096,
  ).unwrap()
  assert_true(
    catalog_observation_identity(next_connection) !=
    catalog_observation_identity(observation),
  )
  assert_eq(
    catalog_observation_resource(observation, binding, "Account").unwrap().name,
    "Account",
  )
  assert_true(
    catalog_observation_resource(
      observation,
      { ..binding, connection_revision: "next", },
      "Account",
    )
    is Err(ForeignBinding),
  )
  assert_true(
    catalog_observation_resource(
      observation,
      { ..binding, site_generation: 5, },
      "Account",
    )
    is Err(ForeignBinding),
  )
  assert_true(
    catalog_observation_resource(observation, binding, "Missing")
    is Err(Resource(NotVisible)),
  )
  let source_resource = match catalog_sync_outcome(sync, "Account") {
    Some(Described(resource)) => resource
    _ => abort("expected described Account")
  }
  ignore(source_resource.fields.pop())
  assert_eq(
    catalog_observation_resource(observation, binding, "Account").unwrap().fields.length(),
    1,
  )
  let returned = catalog_observation_resource(observation, binding, "Account").unwrap()
  ignore(returned.fields.pop())
  assert_eq(
    catalog_observation_resource(observation, binding, "Account").unwrap().fields.length(),
    1,
  )
}

///|
test "catalog observation rejects missing evidence and bounded body overflow" {
  let sync = observation_test_sync()
  finish_catalog_sync(sync).unwrap()
  let binding = observation_test_binding()
  let use_cid = "sha256:" + "c".repeat(64)
  let response_digest = match catalog_sync_outcome(sync, "Account") {
    Some(Described(resource)) => resource.response_sha256
    _ => abort("expected described Account")
  }
  assert_true(
    prepare_catalog_observation(sync, binding, use_cid, [], [], 4096)
    is Err(EvidenceCountMismatch),
  )
  assert_true(
    prepare_catalog_observation(
      sync,
      binding,
      use_cid,
      [None],
      [Some(response_digest)],
      4096,
    )
    is Err(InvalidUseEvidence),
  )
  assert_true(
    prepare_catalog_observation(
      sync,
      binding,
      "invalid",
      [Some(use_cid)],
      [Some(response_digest)],
      4096,
    )
    is Err(InvalidUseEvidence),
  )
  assert_true(
    prepare_catalog_observation(
      sync,
      { ..binding, run_invocation_cid: "invalid", },
      use_cid,
      [Some(use_cid)],
      [Some(response_digest)],
      4096,
    )
    is Err(InvalidBinding),
  )
  assert_true(
    prepare_catalog_observation(
      sync,
      binding,
      use_cid,
      [Some(use_cid)],
      [Some(response_digest)],
      32,
    )
    is Err(OutputLimit),
  )
  assert_true(
    prepare_catalog_observation(
      sync,
      binding,
      use_cid,
      [Some(use_cid)],
      [Some("0".repeat(64))],
      4096,
    )
    is Err(InvalidUseEvidence),
  )
}
