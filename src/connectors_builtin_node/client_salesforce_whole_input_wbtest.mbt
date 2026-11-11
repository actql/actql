///|
// Actual Catalog/check/compiler/RowInput originals. Provider transport,
// Account and physical cleanup remain outside these typed component cases.
fn salesforce_whole_observation(
  connection_revision? : String = "connection-a",
) -> (
  @salesforce_catalog.CatalogObservation,
  @salesforce_catalog.CatalogObservationBinding,
) raise {
  let listing = @salesforce_catalog.project_resource_listing(
    @utf8.encode(
      (
        #|{"sobjects":[{"name":"Account","queryable":true}]}
      ),
    ),
    {
      max_bytes: 2000,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = @salesforce_catalog.begin_catalog_sync(listing)
  let description = @utf8.encode(
    (
      #|{"name":"Account","queryable":true,"fields":[{"name":"Id","type":"id","nillable":false},{"name":"Name","type":"string","nillable":false}]}
    ),
  )
  @salesforce_catalog.catalog_sync_describe(sync, "Account", description, {
    max_bytes: 2000,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 10,
    max_name_units: 100,
  }).unwrap()
  @salesforce_catalog.finish_catalog_sync(sync).unwrap()
  let binding : @salesforce_catalog.CatalogObservationBinding = {
    namespace_id: "namespace-a",
    principal: "principal-a",
    environment: "test",
    connection_revision,
    org_id: "00D000000000001EAA",
    site_key: "site-a",
    site_generation: 1,
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: "https://salesforce.invalid",
    run_invocation_cid: "sha256:" + "a".repeat(64),
    dispatch_request_cid: "sha256:" + "b".repeat(64),
    sync_occurrence: "original",
  }
  let observation = match
    @salesforce_catalog.prepare_catalog_observation(
      sync,
      binding,
      "sha256:" + "c".repeat(64),
      [Some("sha256:" + "d".repeat(64))],
      [Some(@salesforce_catalog.catalog_response_sha256(description))],
      10000,
    ) {
    Ok(value) => value
    Err(issue) =>
      fail("original Describe fixture: " + issue.to_repr().to_string())
  }
  (observation, binding)
}

///|
fn salesforce_whole_declaration(
  observation : @salesforce_catalog.CatalogObservation,
  binding : @salesforce_catalog.CatalogObservationBinding,
  connector_id? : String = "crm-main",
) -> @salesforce_host.InstalledSalesforceDeclaration {
  let limits : @salesforce_catalog.DeclarationLimits = {
    max_bytes: 200000,
    max_nodes: 20000,
    max_depth: 32,
  }
  let declared = @salesforce_catalog.generate_static_declaration(
    observation,
    binding,
    @salesforce_catalog.salesforce_implementation("salesforce/0.1").unwrap(),
    connector_id,
    ["Account"],
    limits,
  ).unwrap()
  let site = @salesforce_host.installed_salesforce_site(
    binding.namespace_id,
    binding.principal,
    binding.environment,
    binding.connection_revision,
    binding.org_id,
    binding.site_key,
    binding.site_generation,
    binding.resource_origin,
  ).unwrap()
  @salesforce_host.restore_installed_salesforce_declaration(
    site,
    observation,
    connector_id,
    declared.catalog_cid,
    limits,
  ).unwrap()
}

///|
fn salesforce_whole_members(
  existing : Json?,
  bodies : Array[String],
) -> Json raise {
  guard existing is Some(Array(entries)) else { fail("fixture members") }
  let members = entries.copy()
  for body in bodies {
    members.push(@json.parse(body))
  }
  let ordered : Array[(String, Json)] = []
  for body in members {
    let value = @identity.from_json(body, 100000, 100, 1000000)
    let cid = @identity.cid_value(value, 1000000, 100000, 100)
    if !ordered.any(entry => entry.0 == cid) {
      ordered.push((cid, body))
    }
  }
  ordered.sort_by((left, right) => left.0.compare(right.0))
  Json::array(ordered.map(entry => entry.1))
}

///|
fn salesforce_whole_environment(
  declaration : @client_row_source_host.RowDeclaration,
) -> @program_check.CheckEnvironment raise {
  let parsed = @json.parse(
    request_capture_bridge_source_query_original_environment,
  )
  guard parsed is Object(base) else { fail("fixture Environment") }
  base.remove("evidence_bundle_cid")
  let (schemas, capabilities) = @client_row_source_host.row_declaration_evidence_members(
    declaration,
  )
  for
    (name, bodies) in [
      ("connector_catalogs", [declaration.catalog]),
      ("contract_registry", declaration.contracts),
      ("source_views", declaration.view_bodies),
      ("schema_snapshots", schemas),
      ("connector_capabilities", capabilities),
    ] {
    base[name] = salesforce_whole_members(base.get(name), bodies)
  }
  guard base.get("connector_manifest") is Some(Object(manifest)) else {
    fail("fixture manifest")
  }
  manifest["connectors"] = salesforce_whole_members(
    manifest.get("connectors"),
    [declaration.manifest_entry],
  )
  let evidence = @identity.cid_value(
    @identity.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  base["evidence_bundle_cid"] = evidence.to_json()
  let wire = @identity.stringify_value(
    @identity.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  match
    @check_environment.read(@utf8.encode(wire), evidence, {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    }) {
    Ok(_) => ()
    Err(issue) =>
      fail("original Environment fixture: " + issue.to_repr().to_string())
  }
  client_program_check_environment(
    wire, evidence, false, false, true, false, false, false, false,
  ).unwrap()
}

///|
fn salesforce_whole_acquisition(
  declaration : @salesforce_host.InstalledSalesforceDeclaration,
) -> @client_row_source_host.RowInputAcquisition raise {
  let rows = client_program_salesforce_row_declaration(declaration).unwrap()
  let environment = salesforce_whole_environment(rows)
  let document =
    #|{"version":"actql/0.1","id":"salesforce-whole-input","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm-main","resource":"Account"}},"steps":[{"filter":"Name <> 'record-2'","as":"filtered"},{"select":["Id","Name"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["Id","Name"]}}}],"results":{"records":{"from":{"stage":"acquire","result":"r"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    @stage_syntax.Json,
    environment,
    None,
    client_program_standard_limits(),
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-salesforce-whole-input",
  ).unwrap()
  guard @client_local_host.select_installed_source_input(
      prepared, request, 0, 0,
    )
    is Ok(@acquisition.WholeInputRoute(original)) else {
    fail("the same root Result must select its complete original input")
  }
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    None,
  ).unwrap()
  let capacity = @client_local_host.prepare_installed_whole_source_capacity(
    prepared,
    original,
    rows,
    contracts,
    {
      max_rows: 100,
      page: { max_bytes: 4096, max_nodes: 1000, max_depth: 20, max_rows: 100, },
      retention: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 20,
        max_work: 1000000,
      },
      wire: {
        max_columns: 2,
        max_order_work: 10000,
        max_bytes: 20000,
        max_nodes: 10000,
        max_depth: 20,
      },
    },
    @execution.execution_capacity(0L, 0L),
  ).unwrap()
  let acquisition = @client_local_host.installed_whole_source_acquisition(
    capacity,
  )
  assert_true(
    @client_row_source_host.row_input_acquisition_matches_source(
      acquisition, original,
    ),
  )
  assert_eq(
    @client_row_source_host.row_input_acquisition_request_wire(acquisition).unwrap(),
    "{}",
  )
  acquisition
}

///|
test "Salesforce full input bridge retains actual input contracts and leaves the authored filter residual" {
  let (current, binding) = salesforce_whole_observation()
  let declaration = salesforce_whole_declaration(current, binding)
  let acquisition = salesforce_whole_acquisition(declaration)
  let plan = client_program_recheck_salesforce_input_projection(
    declaration, acquisition, current, 4096,
  ).unwrap()
  assert_eq(@salesforce_catalog.read_projection_resource(plan), "Account")
  assert_eq(
    @salesforce_catalog.read_projection_soql(plan),
    "SELECT Id,Name FROM Account",
  )
  assert_false(@salesforce_catalog.read_projection_has_prefilter(plan))
  let columns = @client_row_source_host.row_input_acquisition_columns(
    acquisition,
  )
  assert_eq(columns, ["Id", "Name"])
  for index, _ in @salesforce_catalog.read_projection_fields(plan) {
    assert_true(
      physical_equal(
        plan.contracts[index],
        @client_row_source_host.row_input_acquisition_column_contract(
          acquisition, index,
        ).unwrap(),
      ),
    )
  }
}

///|
test "Salesforce full input bridge rejects another declaration or current Site without Query casting" {
  let (current, binding) = salesforce_whole_observation()
  let declaration = salesforce_whole_declaration(current, binding)
  let acquisition = salesforce_whole_acquisition(declaration)
  let other = salesforce_whole_declaration(
    current,
    binding,
    connector_id="other-crm",
  )
  assert_true(
    client_program_recheck_salesforce_input_projection(
      other, acquisition, current, 4096,
    )
    is Err(@salesforce_host.UndeclaredSource),
  )
  let (foreign, _) = salesforce_whole_observation(
    connection_revision="foreign-revision",
  )
  assert_true(
    client_program_recheck_salesforce_input_projection(
      declaration, acquisition, foreign, 4096,
    )
    is Err(@salesforce_host.ForeignBinding),
  )
  assert_true(
    client_program_recheck_salesforce_input_projection(
      declaration, acquisition, current, 1,
    )
    is Err(@salesforce_host.Projection(@salesforce_catalog.QueryLimit)),
  )
}

///|
extern "js" fn salesforce_whole_legacy_effect_input_call(
  prepare : (
    @client_row_source_host.RowDeclaration,
    @execution.ExecutionCapacity?,
    @client_row_source_host.RowInputLimits?,
  ) -> Result[
    @client_local_host.ClientInstalledEffectSourceInput,
    @client_local_host.ClientInstalledManagedRunIssue,
  ],
  declaration : @client_row_source_host.RowDeclaration,
) -> Result[
  @client_local_host.ClientInstalledEffectSourceInput,
  @client_local_host.ClientInstalledManagedRunIssue,
] =
  #|(prepare, declaration) => prepare(declaration, undefined)

///|
test "Effect row input bridge keeps the existing two-argument JavaScript constructor" {
  let (observation, binding) = salesforce_whole_observation()
  let declaration = client_program_salesforce_row_declaration(
    salesforce_whole_declaration(observation, binding),
  ).unwrap()
  // An omitted policy is the original Query constructor, never a Whole
  // fallback. Whole Plan construction separately requires its selected policy.
  salesforce_whole_legacy_effect_input_call(
    client_program_installed_effect_row_source_input_prepare, declaration,
  ).unwrap()
  |> ignore
  let policy = client_program_installed_row_input_policy(
    128, 2097152, 10000, 32, 128,
  )
  client_program_installed_effect_row_source_input_prepare(
    declaration,
    None,
    Some(policy),
  ).unwrap()
  |> ignore
}
