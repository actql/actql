///|
fn hubspot_effect_request_quote() -> @execution.ExecutionCapacity {
  client_program_hubspot_effect_constructor_capacity(
    0,
    [
      4096, 1000, 20, 10, 100, 1000, 4096, 10000, 4096, 1000, 20, 100, 100, 100,
      10000, 1000, 20, 1, 100, 10, 10000, 1000, 20,
    ],
    [],
    [1, 6, 512],
  ).unwrap()
}

///|
test "HubSpot actual typed recipe adds cold marked output once and keeps original target workspace" {
  let request = hubspot_effect_request_quote()
  let finalization = client_program_hubspot_effect_constructor_capacity(
    6,
    [
      4096, 1000, 20, 10, 100, 1000, 4096, 10000, 4096, 1000, 20, 100, 100, 100,
      10000, 1000, 20, 1, 100, 10, 10000, 1000, 20,
    ],
    [],
    [1, 6, 512],
  ).unwrap()
  let target = client_program_hubspot_effect_constructor_capacity(
    1,
    [32, 32, 8, 1, 10, 32, 32, 64],
    [64, 64, 8],
    [1, 6, 512],
  ).unwrap()
  let response = client_program_hubspot_effect_constructor_capacity(
    2,
    [32, 32, 8],
    [],
    [],
  ).unwrap()
  let metadata = client_program_hubspot_effect_constructor_capacity(
    5,
    [0, 1, 9, 64, 64, 8, 10, 64],
    [],
    [],
  ).unwrap()
  let profile = Some([
    (request, None, None),
    (target, None, None),
    (response, None, None),
    (metadata, None, None),
  ])
  let bounds = [
    256, 16, 4, 128, 8, 2, 64, 32, 16, 32, 16, 64, 16, 7, 32, 256, 64, 4,
  ]
  let warm = client_program_hubspot_effect_recipe_capacities(
    profile,
    Some(finalization),
    bounds,
    0L,
    1,
    0,
    0,
  ).unwrap()
  let cold = client_program_hubspot_effect_recipe_capacities(
    profile,
    Some(finalization),
    bounds,
    0L,
    1,
    0,
    1,
  ).unwrap()
  assert_eq(warm.length(), 8)
  assert_eq(
    @execution.execution_capacity_retained_bytes(cold[1]) -
    @execution.execution_capacity_retained_bytes(warm[1]),
    @execution.execution_capacity_retained_bytes(request) +
    @execution.execution_capacity_retained_bytes(finalization),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(warm[6]) >
    @execution.execution_capacity_retained_bytes(warm[6]),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(warm[7]) >
    @execution.execution_capacity_retained_bytes(warm[7]),
  )
}

///|
fn hubspot_effect_original_inputs() -> (
  @hubspot_catalog.PropertyCatalog,
  @hubspot_catalog.ExecutionMapping,
) {
  let catalog = @hubspot_catalog.project_properties(
    b"{\"results\":[{\"name\":\"amount\",\"type\":\"number\",\"fieldType\":\"number\",\"calculated\":false,\"modificationMetadata\":{\"readOnlyValue\":false}},{\"name\":\"actql_request_id\",\"type\":\"string\",\"fieldType\":\"text\",\"calculated\":false,\"modificationMetadata\":{\"readOnlyValue\":false}}]}",
    "companies",
    {
      max_bytes: 8192,
      max_nodes: 2000,
      max_depth: 24,
      max_properties: 100,
      max_name_units: 256,
    },
  ).unwrap()
  let mapping = @hubspot_catalog.prepare_execution_mapping(
    catalog,
    "hubspot",
    "sha256:" + "a".repeat(64),
    "companies",
    Update,
    ["amount"],
    [],
    {
      max_properties: 100,
      max_fields: 10,
      max_name_bytes: 100,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    },
  ).unwrap()
  (catalog, mapping)
}

///|
fn hubspot_effect_request_original(
  original : (
    @hubspot_catalog.PropertyCatalog,
    @hubspot_catalog.ExecutionMapping,
  ),
) -> String raise {
  let (catalog, mapping) = original
  let body_limits : @hubspot_catalog.WriteBodyLimits = {
    max_input_bytes: 4096,
    max_nodes: 1000,
    max_depth: 20,
    max_fields: 10,
    max_name_bytes: 100,
    max_value_nodes: 1000,
    max_value_text_bytes: 4096,
    max_comparison_work: 10000,
    max_output_bytes: 4096,
    max_output_nodes: 1000,
    max_output_depth: 20,
  }
  let body = @hubspot_catalog.prepare_execution_write_body(
    mapping, catalog, b"{\"amount\":\"9007199254740993.0100000000\"}", 100, body_limits,
  ).unwrap()
  let target = @hubspot_catalog.prepare_record_target(
    catalog, "id", b"\"9007199254740993\"", body_limits,
  ).unwrap()
  let read = @hubspot_catalog.prepare_record_read_request(
    catalog,
    [target],
    ["amount"],
    {
      max_rows: 1,
      max_properties: 100,
      max_columns: 10,
      max_request_bytes: 10000,
      max_request_nodes: 1000,
      max_request_depth: 20,
    },
  ).unwrap()
  assert_eq(
    @hubspot_catalog.record_read_request_body(read),
    "{\"inputs\":[{\"id\":\"9007199254740993\"}],\"properties\":[\"amount\"]}",
  )
  let marker = @hubspot_catalog.prepare_record_request_marker(
    catalog,
    "actql_request_id",
    "sha256:" + "b".repeat(64),
    body_limits,
  ).unwrap()
  let request = @hubspot_catalog.prepare_marked_record_batch_request(
    catalog,
    Update,
    [{ body, target: Some(target), trace_id: "original-correlation", }],
    marker,
    {
      max_rows: 100,
      max_properties: 100,
      max_trace_bytes: 100,
      max_body_bytes: 10000,
      max_body_nodes: 1000,
      max_body_depth: 20,
    },
  ).unwrap()
  @hubspot_catalog.record_batch_request_body(request)
}

///|
test "HubSpot Effect actual Common issuer and Ledger fund original request then shrink only after successful return" {
  // Previously initialized immutable fixture inputs are borrowed by this row
  // constructor. Their initialization is not claimed as funded by this quote.
  let original = hubspot_effect_original_inputs()
  let ledger = hubspot_mapping_initialization_ledger(536870912L)
  let input = [1]
  let owner : @resources.PreparationCapacity[
    Array[Int],
    (Array[Int], @source_publication.PreparedPublishedQueryEnvironment),
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    0L,
    0L,
    max_borrowers=2,
  ).unwrap()
  let quote = hubspot_effect_request_quote()
  let running = client_program_compose_installed_source_construction_capacity(
    @execution.execution_capacity(0L, 0L).unwrap(),
    [Some(quote)],
  ).unwrap()
  @client_local_host.reserve_installed_source_construction(
    owner, input, running,
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(quote)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, peak)
  let wire = hubspot_effect_request_original(original)
  assert_true(wire.contains("9007199254740993.0100000000"))
  assert_true(
    wire.contains("\"actql_request_id\":\"sha256:" + "b".repeat(64) + "\""),
  )
  let retained = client_program_installed_source_retained_construction_capacity(
      Some(quote),
    )
    .unwrap()
    .unwrap()
  assert_true(
    @client_local_host.reconcile_installed_source_construction(
      owner,
      [1],
      retained,
    )
    is Err(@resources.ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, peak)
  @client_local_host.reconcile_installed_source_construction(
    owner, input, retained,
  ).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    @execution.execution_capacity_retained_bytes(quote),
  )
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(owner, input).unwrap(),
  )
}

///|
test "HubSpot Effect real Ledger refuses one-short constructor peak before original projection" {
  let original = hubspot_effect_original_inputs()
  let quote = hubspot_effect_request_quote()
  let peak = @execution.execution_capacity_execution_bytes(quote)
  let ledger = hubspot_mapping_initialization_ledger(peak - 1L)
  let input = [2]
  let owner : @resources.PreparationCapacity[
    Array[Int],
    (Array[Int], @source_publication.PreparedPublishedQueryEnvironment),
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    0L,
    0L,
    max_borrowers=2,
  ).unwrap()
  let running = client_program_compose_installed_source_construction_capacity(
    @execution.execution_capacity(0L, 0L).unwrap(),
    [Some(quote)],
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let mut projects = 0
  match
    @client_local_host.reserve_installed_source_construction(
      owner, input, running,
    ) {
    Ok(_) => {
      projects += 1
      ignore(hubspot_effect_request_original(original))
    }
    Err(@resources.Resource(_)) => ()
    Err(_) => fail("Expected original Resource refusal")
  }
  assert_eq(projects, 0)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(owner, input).unwrap(),
  )
}

///|
test "HubSpot private constructor port refuses unknown tags and incomplete quantity vectors" {
  assert_true(
    client_program_hubspot_effect_constructor_capacity(99, [], [], []) is None,
  )
  assert_true(
    client_program_hubspot_effect_constructor_capacity(0, [], [], [1, 6, 512])
    is None,
  )
  assert_true(
    client_program_hubspot_effect_constructor_capacity(
      1,
      [8192, 2000, 24, 1, 10, 256, 2000, 8192, 0],
      [8192, 2000, 24],
      [1, 6, 512],
    )
    is None,
  )
  assert_true(
    client_program_hubspot_effect_recipe_capacities(None, None, [], 0L, 1, 0, 0)
    is Err(Unsupported),
  )
}

///|
test "HubSpot private installation quote keeps full original resource inventory separate from installed writes" {
  let original = client_program_hubspot_effect_constructor_capacity(7, [], [], [
    1, 2, 3, 1024,
  ]).unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(original) > 0L)
  assert_true(
    @execution.execution_capacity_execution_bytes(original) >
    @execution.execution_capacity_retained_bytes(original),
  )
  assert_true(
    client_program_hubspot_effect_constructor_capacity(7, [], [], [1, 2, 3])
    is None,
  )
  assert_true(
    client_program_hubspot_effect_constructor_capacity(7, [], [], [
      2, 2, 1, 1024,
    ])
    is None,
  )
}
