///|
fn current_salesforce_query_fixture() -> @salesforce_catalog.QueryRead {
  let listing = @salesforce_catalog.project_resource_listing(
    @utf8.encode("{\"sobjects\":[{\"name\":\"Account\",\"queryable\":true}]}"),
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = @salesforce_catalog.begin_catalog_sync(listing)
  @salesforce_catalog.catalog_sync_describe(
    sync,
    "Account",
    @utf8.encode(
      "{\"name\":\"Account\",\"queryable\":true,\"fields\":[{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false}]}",
    ),
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_fields: 10,
      max_name_units: 100,
    },
  ).unwrap()
  @salesforce_catalog.finish_catalog_sync(sync).unwrap()
  let digest = match @salesforce_catalog.catalog_sync_outcome(sync, "Account") {
    Some(Described(resource)) => resource.response_sha256
    _ => abort("fixture Describe missing")
  }
  let binding : @salesforce_catalog.CatalogObservationBinding = {
    namespace_id: "namespace-a",
    principal: "principal-a",
    environment: "test",
    connection_revision: "connection-a",
    org_id: "00D000000000001EAA",
    site_key: "site-a",
    site_generation: 1,
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: "https://example.invalid",
    run_invocation_cid: "sha256:" + "a".repeat(64),
    dispatch_request_cid: "sha256:" + "b".repeat(64),
    sync_occurrence: "sync-a",
  }
  let observation = @salesforce_catalog.prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [Some(digest)],
    4096,
  ).unwrap()
  let plan = @salesforce_catalog.prepare_read_projection(
    observation,
    binding,
    "Account",
    ["Id"],
    4096,
  ).unwrap()
  @salesforce_catalog.begin_query_read(
    plan,
    "v62.0",
    {
      max_bytes: 4000000,
      max_nodes: 400000,
      max_depth: 32,
      max_rows: 2000,
      max_locator_units: 2048,
    },
    10,
    100L,
  ).unwrap()
}

///|
test "current Salesforce bridge quotes long original body without future raw totals" {
  let limits = [
    4000000, 48000000, 400000, 32, 2000, 100, 12, 2000, 2048, 4000000, 24002944,
    400000, 4000000, 4000000, 400000, 32,
  ]
  let describe = [4000000, 400000, 32, 1000, 200000]
  let initial = client_program_installed_salesforce_current_response_capacity(
    limits,
    100,
    65536,
    describe,
    8000000,
    306,
    14,
    10,
    5,
    4096,
    0,
    None,
    "",
    None,
    0L,
    0,
  ).unwrap()
  let read = current_salesforce_query_fixture()
  let path = @salesforce_catalog.query_read_next_path(read).unwrap().unwrap()
  let body = @utf8.encode(
    "{\"totalSize\":1,\"done\":true,\"records\":[{\"Id\":\"" +
    "x".repeat(232000) +
    "\"}]}",
  )
  let next = client_program_installed_salesforce_current_response_capacity(
    limits,
    100,
    65536,
    describe,
    8000000,
    306,
    14,
    10,
    5,
    4096,
    557,
    Some(read),
    path,
    Some(body),
    body.length().to_int64() + 1114L,
    3,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(initial) < 100000000L,
  )
  assert_true(@execution.execution_capacity_execution_bytes(next) < 100000000L)
  assert_true(@execution.execution_capacity_retained_bytes(next) < 10000000L)
  assert_false(@salesforce_catalog.query_read_complete(read))
  let copied = @utf8.encode(
    "{\"totalSize\":1,\"done\":true,\"records\":[{\"Id\":\"" +
    "x".repeat(232000) +
    "\"}]}",
  )
  assert_true(
    @salesforce_catalog.query_read_accept_page(read, path, copied)
    is Err(WrongPage),
  )
}
