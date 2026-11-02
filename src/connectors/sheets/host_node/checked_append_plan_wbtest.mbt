///|
// Original public append declaration/Mapping and two equal logical rows.
// Quote only: no Site, permission, provider I/O or physical cleanup evidence.
test "standard append keeps two equal occurrences within the existing Local preparation policy" {
  let columns = "[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false},{\"name\":\"number\",\"type\":\"number\",\"nullable\":true},{\"name\":\"flag\",\"type\":\"boolean\",\"nullable\":true}]"
  let views = "{\"views\":[{\"resource\":\"rows\",\"resource_kind\":\"sheet_rows\",\"fields\":" +
    columns +
    "}]}"
  let declaration = @row_source_host.restore_row_declaration(
    "sheets-book",
    "sheets",
    "sheets/0.1",
    views,
    None,
  ).unwrap()
  let writes = "{\"writes\":[{\"resource\":\"append_rows\",\"resource_kind\":\"sheet_collection\",\"primary_identity\":null,\"collection_identity\":{\"spreadsheet_id\":\"book\",\"sheet_id\":7},\"fields\":" +
    columns +
    ",\"create\":{\"fields\":[\"text\",\"number\",\"flag\"],\"required\":[\"text\",\"number\",\"flag\"],\"permission\":\"sheets:cells:append\",\"approval\":\"required\"}}]}"
  let mapping = @row_source_host.prepare_row_mapping(
    declaration,
    writes,
    "append_rows",
    ["text", "number", "flag"].map(name => {
      target: name,
      field: name,
      null_behavior: "reject",
    }),
  ).unwrap()
  let (schemas, capabilities) = @row_source_host.row_declaration_evidence_members(
    declaration,
  )
  guard @json.parse(sheets_checked_plan_environment) is Object(base) else {
    fail("original Environment")
  }
  base.remove("evidence_bundle_cid") |> ignore
  for
    (name, members) in [
      ("schema_snapshots", schemas),
      ("connector_capabilities", capabilities),
      ("source_views", declaration.view_bodies),
      ("contract_registry", declaration.contracts),
      ("mapping_contracts", [mapping.body]),
    ] {
    base[name] = sheets_checked_plan_members(members)
  }
  base["connector_catalogs"] = Json::array([@json.parse(declaration.catalog)])
  base["connector_manifest"] = {
    "version": "actql-connectors/0.1",
    "connectors": [@json.parse(declaration.manifest_entry)],
  }
  let evidence = "sha256:" +
    @sha.hex(@utf8.encode(sheets_checked_plan_wire(Json::object(base))))
  base["evidence_bundle_cid"] = evidence.to_json()
  let environment = @publication_host.admit_client_check_environment(
    sheets_checked_plan_wire(Json::object(base)),
    evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  guard @json.parse(mapping.body) is Object(body) &&
    body["target_ref"] is String(target) else {
    fail("original Mapping target")
  }
  let program = "{\"version\":\"actql/0.1\",\"id\":\"sheets-append\",\"stages\":[{\"id\":\"write\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"text\":{\"type\":\"string\",\"nullable\":false},\"number\":{\"type\":\"number\",\"nullable\":true},\"flag\":{\"type\":\"boolean\",\"nullable\":true}},\"rows\":[{\"text\":\"same\",\"number\":0,\"flag\":false},{\"text\":\"same\",\"number\":0,\"flag\":false}]},\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"text\",\"number\",\"flag\"]}},\"effects\":{\"append\":{\"create\":{\"target\":\"" +
    target +
    "\",\"mapping\":\"" +
    mapping.mapping_ref +
    "\",\"from\":{\"result\":\"rows\"}}}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"write\",\"result\":\"rows\"}}}}"
  let prepared = @publication_host.prepare_client_effect_computation(
    program,
    Json,
    environment,
    None,
    [],
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "sheets-append",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let contracts = @client_host.prepare_installed_sequence_contracts(
    sheets_checked_plan_registry,
    sheets_checked_plan_values,
    Some(sheets_checked_plan_fragment),
    None,
  ).unwrap()
  let native = sheets_append_request_construction_profile(
    @utf8.encode(columns).length(),
    3,
    100000,
    10000,
    16,
    300000,
    2000000,
    200000,
    32,
  )
  // Original implementation ceilings; zero metadata text is a disclosed
  // lower-bound fixture, not complete normal installation backing.
  let capacities = @client_host.installed_standard_create_request_recipe_capacities(
    native,
    1000000,
    100000,
    64,
    100000,
    10000,
    16,
    300000,
    2000000,
    300000,
    2000000,
    false,
    65536,
    7,
    16384,
    1000000,
    512,
    16,
    0L,
    response_read_quantum=16384,
  ).unwrap()
  for index in 0..<capacities.length() {
    println(
      "APPEND_PHASE \{index} retained=\{@execution.execution_capacity_retained_bytes(capacities[index])} execution=\{@execution.execution_capacity_execution_bytes(capacities[index])}",
    )
  }
  let capture = @client_host.prepare_installed_effect_capture_extent(
    "sheets:cells:append",
    capacities[0],
    capacities[1],
  ).unwrap()
  let construct = @client_host.prepare_installed_effect_operation_extent(
    "sheets:cells:append",
    capacities[2],
    0L,
    false,
  ).unwrap()
  let reads = [0, 1, 2].map(_ => {
    @client_host.prepare_installed_effect_operation_extent(
      "sheets:grid:read",
      capacities[5],
      2300000L,
      true,
    ).unwrap()
  })
  let write = @client_host.prepare_installed_effect_operation_extent(
    "sheets:cells:append",
    capacities[3],
    2300000L,
    true,
  ).unwrap()
  let demand = @client_host.prepare_installed_effect_operation_demand_with_controls(
    prepared,
    0,
    "append",
    [capture],
    [construct, ..reads, write],
    capacities[4],
  ).unwrap()
  let plan = @client_host.prepare_installed_effect_managed_plan(
    prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    sheets_checked_plan_values,
    Some(sheets_checked_plan_fragment),
    None,
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  let (rows, members, _) = @client_host.prepared_installed_effect_managed_shape(
    plan,
  )
  assert_eq(rows, 2)
  assert_eq(members, 1)
  let required = @client_host.prepared_installed_effect_managed_requirements(
    plan,
  )
  assert_eq(required[1], 9L)
  let admitted = @client_host.client_local_preparation_initial_limits(
    @client_host.client_local_resource_policy(),
  ).unwrap()
  println("APPEND_PLAN retained=\{required[4]} execution=\{required[5]}")
  assert_true(required[4] <= admitted.retained_bytes)
  assert_true(required[5] <= admitted.execution_bytes)
}
