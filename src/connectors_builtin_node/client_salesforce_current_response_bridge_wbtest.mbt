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

///|
test "current Describe quotes original JSON geometry instead of one node per text byte" {
  let limits = [
    4000000, 48000000, 400000, 32, 2000, 100, 12, 2000, 2048, 4000000, 24002944,
    400000, 4000000, 4000000, 400000, 32,
  ]
  let body = @utf8.encode(
    "{\"name\":\"Account\",\"queryable\":true,\"description\":\"" +
    "a".repeat(250000) +
    "\",\"fields\":[{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false}]}",
  )
  let capacity = client_program_installed_salesforce_current_response_capacity(
    limits,
    100,
    65536,
    [4000000, 400000, 32, 1000, 200000],
    8000000,
    306,
    14,
    10,
    5,
    4096,
    body.length(),
    None,
    "/services/data/v62.0/sobjects/Account/describe",
    Some(body),
    body.length().to_int64(),
    1,
  ).unwrap()
  // The unchanged normal parent is512MiB. A long scalar is not250000 JSON
  // nodes or1000 observed metadata fields. This is demand, never admission.
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) < 536870912L,
  )
}

///|
test "Describe syntax preflight preserves retained families and original refusal envelopes" {
  let limits = [
    4000000, 48000000, 400000, 32, 2000, 100, 12, 2000, 2048, 4000000, 24002944,
    400000, 4000000, 4000000, 400000, 32,
  ]
  let describe = [4000000, 400000, 32, 1000, 200000]
  let body = @utf8.encode("{\"description\":\"" + "a".repeat(250000) + "\"}")
  let quote = (body : Bytes?) => {
    client_program_installed_salesforce_current_response_capacity(
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
      250018,
      None,
      "/services/data/v62.0/sobjects/Account/describe",
      body,
      250018L,
      1,
    ).unwrap()
  }
  let measured = quote(Some(body))
  let complete = quote(None)
  // Two previous/current metadata families and failed prefixes keep the old
  // complete envelope. ONLY the sequential current parser/index shrinks.
  assert_eq(
    @execution.execution_capacity_retained_bytes(measured),
    @execution.execution_capacity_retained_bytes(complete),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(measured) <
    @execution.execution_capacity_execution_bytes(complete),
  )
  assert_eq(
    body,
    @utf8.encode("{\"description\":\"" + "a".repeat(250000) + "\"}"),
  )
  for malformed in ["{", "[0,", "not-json"] {
    let original = @utf8.encode(malformed)
    // Syntax geometry is not grammar/Catalog admission. A lexical prefix
    // can have a complete construction bound while the real parser refuses.
    assert_true(
      @source.parse_json_bytes(original, {
        max_input_bytes: describe[0],
        max_nodes: describe[1],
        max_depth: describe[2],
      })
      is Err(_),
    )
    assert_eq(original, @utf8.encode(malformed))
  }
  assert_true(
    @source.parse_json_bytes(body, {
      max_input_bytes: describe[0],
      max_nodes: 1,
      max_depth: describe[2],
    })
    is Err(_),
  )
  // An input-byte refusal never creates a decoded/preflight allocation.
  assert_true(
    installed_salesforce_describe_source_geometry(body, [
      1, 400000, 32, 1000, 200000,
    ])
    is None,
  )
}

///|
test "current query workspace does not reopen an already completed Describe parser" {
  let limits = [
    4000000, 48000000, 400000, 32, 2000, 100, 12, 2000, 2048, 4000000, 24002944,
    400000, 4000000, 4000000, 400000, 32,
  ]
  let read = current_salesforce_query_fixture()
  let path = @salesforce_catalog.query_read_next_path(read).unwrap().unwrap()
  let body = @utf8.encode(
    "{\"totalSize\":1,\"done\":true,\"records\":[{\"Id\":\"original-row\"}]}",
  )
  let capacity = client_program_installed_salesforce_current_response_capacity(
    limits,
    100,
    65536,
    [4000000, 400000, 32, 1000, 200000],
    8000000,
    306,
    14,
    10,
    5,
    4096,
    251217,
    Some(read),
    path,
    Some(body),
    502434L + body.length().to_int64(),
    3,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) < 536870912L,
  )
  assert_false(@salesforce_catalog.query_read_complete(read))
}

///|
test "query phase retains metadata families while the unentered metadata phase keeps its workspace" {
  let read = current_salesforce_query_fixture()
  let path = @salesforce_catalog.query_read_next_path(read).unwrap().unwrap()
  let body = @utf8.encode(
    "{\"totalSize\":1,\"done\":true,\"records\":[{\"Id\":\"row\"}]}",
  )
  let geometry = @salesforce_catalog.prepare_query_read_response(
    read, path, body,
  ).unwrap()
  let quote = (active : Bool) => {
    @salesforce_host.native_read_construction_capacity(
      {
        max_bytes: 251217,
        max_nodes: 251217,
        max_depth: 32,
        max_fields: 1000,
        max_name_units: 200000,
      },
      {
        max_bytes: body.length(),
        max_nodes: 100,
        max_depth: 32,
        max_rows: 2000,
        max_locator_units: 2048,
      },
      8000000,
      306,
      14,
      1,
      10,
      5,
      4096,
      query_geometry=if active { Some(geometry) } else { None },
      value_nodes=Some(1),
    ).unwrap()
  }
  let current = quote(true)
  let before = quote(false)
  assert_eq(
    @execution.execution_capacity_retained_bytes(current),
    @execution.execution_capacity_retained_bytes(before),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(current) < 536870912L,
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(before) >= 536870912L,
  )
  assert_false(@salesforce_catalog.query_read_complete(read))
}
