///|
fn salesforce_row_binding() -> @salesforce_catalog.CatalogObservationBinding {
  {
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
}

///|
fn salesforce_row_plan(
  resource? : String = "r",
  native_type? : String = "int",
  filterable? : Bool = false,
  max_soql_bytes? : Int = 100,
) -> @salesforce_catalog.ReadProjection {
  let listing = @salesforce_catalog.project_resource_listing(
    @utf8.encode(
      "{\"sobjects\":[{\"name\":\"" + resource + "\",\"queryable\":true}]}",
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
  let sync = @salesforce_catalog.begin_catalog_sync(listing)
  let description = "{\"name\":\"" +
    resource +
    "\",\"queryable\":true,\"fields\":[{\"name\":\"id\",\"type\":\"" +
    native_type +
    "\",\"nillable\":false,\"filterable\":" +
    filterable.to_string() +
    "}]}"
  @salesforce_catalog.catalog_sync_describe(
    sync,
    resource,
    @utf8.encode(description),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_fields: 10,
      max_name_units: 100,
    },
  ).unwrap()
  @salesforce_catalog.finish_catalog_sync(sync).unwrap()
  let binding = salesforce_row_binding()
  let observation = @salesforce_catalog.prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [
      Some(
        @salesforce_catalog.catalog_response_sha256(@utf8.encode(description)),
      ),
    ],
    4096,
  ).unwrap()
  @salesforce_catalog.prepare_read_projection(
    observation,
    binding,
    resource,
    ["id"],
    max_soql_bytes,
  ).unwrap()
}

///|
/// This Site's declaration for the fixture Resource `r`, from the same
/// describe the plans observe; the checked Program reads its SourceView.
fn salesforce_row_declaration(
  resource? : String = "r",
  connector_id? : String = "crm/main",
  site_generation? : Int = 1,
  filterable? : Bool = false,
) -> @salesforce_catalog.StaticDeclaration {
  let listing = @salesforce_catalog.project_resource_listing(
    @utf8.encode(
      "{\"sobjects\":[{\"name\":\"" + resource + "\",\"queryable\":true}]}",
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
  let sync = @salesforce_catalog.begin_catalog_sync(listing)
  let description = "{\"name\":\"" +
    resource +
    "\",\"queryable\":true,\"fields\":[{\"name\":\"id\",\"type\":\"int\",\"nillable\":false,\"filterable\":" +
    filterable.to_string() +
    "}]}"
  @salesforce_catalog.catalog_sync_describe(
    sync,
    resource,
    @utf8.encode(description),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_fields: 10,
      max_name_units: 100,
    },
  ).unwrap()
  @salesforce_catalog.finish_catalog_sync(sync).unwrap()
  let binding = { ..salesforce_row_binding(), site_generation, }
  let observation = @salesforce_catalog.prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [
      Some(
        @salesforce_catalog.catalog_response_sha256(@utf8.encode(description)),
      ),
    ],
    4096,
  ).unwrap()
  @salesforce_catalog.generate_static_declaration(
    observation,
    binding,
    @salesforce_catalog.salesforce_implementation("salesforce/0.1").unwrap(),
    connector_id,
    [resource],
    { max_bytes: 200000, max_nodes: 20000, max_depth: 32, },
  ).unwrap()
}

///|
fn salesforce_row_catalog() -> @environment.SourceRequestContracts {
  let declaration = salesforce_row_declaration()
  let (wire, cid) = declaration_environment(
    [declaration.catalog],
    declaration.contracts,
    declaration.view_bodies,
    [],
    // The same fixed capacity policy as the existing Program fixture.
    host_policy="{\"capacity\":{\"max_aggregate_array_items\":10000,\"max_artifact_bytes\":10000,\"max_artifact_rows\":10000,\"max_effect_items\":10000,\"max_graph_input_edges\":10000,\"max_graph_input_nodes\":10000,\"max_graph_output_rows\":10000,\"max_graph_paths\":10000,\"max_infer_items\":10000,\"max_model_input_tokens_per_item\":10000,\"max_model_request_bytes_per_item\":10000,\"max_model_total_duration_ms\":10000,\"max_nested_value_bytes\":10000,\"max_nested_value_depth\":10000,\"max_relation_output_rows\":10000,\"max_temporal_matches_per_key\":10000,\"max_temporal_output_rows\":10000,\"version\":\"actql-capacity-host-policy/0.1\"}}",
  )
  query_catalog_from_wire(wire, expected=cid)
}

///|
fn salesforce_row_requirement() -> @planning.QueryRequirement raise {
  let checked = query_checked_program_fixture(
    catalog=Some(salesforce_row_catalog()),
  )
  let sequence = query_checked_sequence(checked)
  @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(checked),
    { max_rows: 2, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
}

///|
test "Salesforce projection binds the exact checked source" {
  let requirement = salesforce_row_requirement()
  let plan = salesforce_row_plan()
  let preparation = @salesforce_host.prepare_salesforce_row_projection(
    requirement,
    plan,
    "crm/main",
    salesforce_row_declaration(),
  ).unwrap()
  assert_true(
    physical_equal(
      @salesforce_host.salesforce_read_requirement(preparation),
      requirement,
    ),
  )
  assert_true(
    @salesforce_host.prepare_salesforce_row_projection(
      requirement,
      plan,
      "foreign/instance",
      salesforce_row_declaration(),
    )
    is Err(ForeignSource),
  )
  assert_true(
    @salesforce_host.prepare_salesforce_row_projection(
      requirement,
      salesforce_row_plan(resource="other"),
      "crm/main",
      salesforce_row_declaration(),
    )
    is Err(ForeignSource),
  )
  assert_true(
    @salesforce_host.prepare_salesforce_row_projection(
      requirement,
      salesforce_row_plan(native_type="string"),
      "crm/main",
      salesforce_row_declaration(),
    )
    is Err(InvalidInputSchema),
  )
}

///|
test "Salesforce pushes an exact checked integer comparison and retains residual" {
  let requirement = salesforce_row_requirement()
  let preparation = @salesforce_host.prepare_salesforce_row_projection(
    requirement,
    salesforce_row_plan(filterable=true),
    "crm/main",
    salesforce_row_declaration(filterable=true),
  ).unwrap()
  assert_eq(
    @salesforce_catalog.read_projection_soql(
      @salesforce_host.salesforce_read_plan(preparation),
    ),
    "SELECT id FROM r WHERE id > 1",
  )
  let unfilterable = @salesforce_host.prepare_salesforce_row_projection(
    requirement,
    salesforce_row_plan(),
    "crm/main",
    salesforce_row_declaration(),
  ).unwrap()
  assert_eq(
    @salesforce_catalog.read_projection_soql(
      @salesforce_host.salesforce_read_plan(unfilterable),
    ),
    "SELECT id FROM r",
  )
  let supplied_filter = @salesforce_catalog.with_exact_int_comparison(
    salesforce_row_plan(filterable=true),
    "id",
    @salesforce_catalog.Greater,
    2,
  ).unwrap()
  assert_true(
    @salesforce_host.prepare_salesforce_row_projection(
      requirement,
      supplied_filter,
      "crm/main",
      salesforce_row_declaration(),
    )
    is Err(UnexpectedPrefilter),
  )
  // A field whose current type has no exact declared contract is refused
  // before any query, even though its name is declared: a read plan and the
  // declaration admit the same types, so no plan of it exists. A Number
  // (`double`) without a described precision up to 15 is one.
  let listing = @salesforce_catalog.project_resource_listing(
    @utf8.encode("{\"sobjects\":[{\"name\":\"r\",\"queryable\":true}]}"),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = @salesforce_catalog.begin_catalog_sync(listing)
  let description = "{\"name\":\"r\",\"queryable\":true,\"fields\":[{\"name\":\"id\",\"type\":\"double\",\"precision\":16,\"scale\":2,\"nillable\":false,\"filterable\":true}]}"
  @salesforce_catalog.catalog_sync_describe(
    sync,
    "r",
    @utf8.encode(description),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_fields: 10,
      max_name_units: 100,
    },
  ).unwrap()
  @salesforce_catalog.finish_catalog_sync(sync).unwrap()
  let binding = salesforce_row_binding()
  let observation = @salesforce_catalog.prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [
      Some(
        @salesforce_catalog.catalog_response_sha256(@utf8.encode(description)),
      ),
    ],
    4096,
  ).unwrap()
  assert_true(
    @salesforce_catalog.prepare_read_projection(
      observation,
      binding,
      "r",
      ["id"],
      100,
    )
    is Err(UnsupportedReadType("id")),
  )
}

///|
test "Salesforce projection requires this Site's declaration of the source" {
  let requirement = salesforce_row_requirement()
  // Another generation of the same connection and schema is foreign.
  assert_true(
    @salesforce_host.prepare_salesforce_row_projection(
      requirement,
      salesforce_row_plan(),
      "crm/main",
      salesforce_row_declaration(site_generation=2),
    )
    is Err(Undeclared(ForeignDeclaration)),
  )
  // The same schema declared under another connection id is foreign.
  assert_true(
    @salesforce_host.prepare_salesforce_row_projection(
      requirement,
      salesforce_row_plan(),
      "crm/main",
      salesforce_row_declaration(connector_id="crm/other"),
    )
    is Err(ForeignSource),
  )
  // A declaration of another Resource does not cover the checked source.
  assert_true(
    @salesforce_host.prepare_salesforce_row_projection(
      requirement,
      salesforce_row_plan(),
      "crm/main",
      salesforce_row_declaration(resource="other"),
    )
    is Err(Undeclared(Undeclared)),
  )
}
