///|
/// A synthetic describe: no real org. Admission of what the Salesforce
/// Connector generates is checked by the existing Check Environment owners.
fn salesforce_declaration_fixture(
  connector_id? : String = "crm-main",
) -> @salesforce_catalog.StaticDeclaration {
  let describe = "{\"name\":\"Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true,\"fields\":[" +
    "{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false,\"createable\":false,\"updateable\":false}," +
    "{\"name\":\"Name\",\"type\":\"string\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}," +
    "{\"name\":\"External_Key__c\",\"type\":\"string\",\"nillable\":false,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true,\"externalId\":true,\"unique\":true}," +
    "{\"name\":\"Count__c\",\"type\":\"int\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true,\"filterable\":true}," +
    "{\"name\":\"Amount__c\",\"type\":\"double\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}" +
    "]}"
  let listing = @salesforce_catalog.project_resource_listing(
    @utf8.encode(
      "{\"sobjects\":[{\"name\":\"Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true}]}",
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
  @salesforce_catalog.catalog_sync_describe(
    sync,
    "Record__c",
    @utf8.encode(describe),
    {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 10,
      max_fields: 20,
      max_name_units: 1000,
    },
  ).unwrap()
  @salesforce_catalog.finish_catalog_sync(sync).unwrap()
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
    [Some(@salesforce_catalog.catalog_response_sha256(@utf8.encode(describe)))],
    4096,
  ).unwrap()
  @salesforce_catalog.generate_static_declaration(
    observation,
    binding,
    @salesforce_catalog.salesforce_implementation("salesforce/0.1").unwrap(),
    connector_id,
    ["Record__c"],
    { max_bytes: 200000, max_nodes: 20000, max_depth: 32, },
  ).unwrap()
}

///|
/// Execution Mappings of the fixture Resource: update of Name and upsert on
/// the external ID, under a placeholder manifest identity.
fn salesforce_execution_bodies(
  declaration : @salesforce_catalog.StaticDeclaration,
) -> Array[String] {
  [
    @salesforce_catalog.UpdateById(["Name"]),
    @salesforce_catalog.UpsertByExternalId("External_Key__c", ["Name"]),
  ].map(write => {
    @salesforce_catalog.prepare_execution_mapping(
      declaration,
      "Record__c",
      write,
      { max_bytes: 200000, max_nodes: 20000, max_depth: 32, },
    ).unwrap().body
  })
}

///|
fn text_cid(text : String) -> String {
  "sha256:" + @sha.hex(@utf8.encode(text))
}

///|
/// Derived environment arrays are ordered by full-body CID.
fn by_body(texts : Array[String]) -> String {
  let sorted = texts.copy()
  sorted.sort_by((a, b) => text_cid(a).compare(text_cid(b)))
  "[" + sorted.join(",") + "]"
}

///|
/// One canonical Check Environment holding the given Catalogs and Mappings,
/// with members in canonical key order and its evidence CID sealed last.
fn declaration_environment(
  catalogs : Array[String],
  contracts : Array[String],
  views : Array[String],
  mappings : Array[String],
  host_policy? : String = "{}",
  manifest_entries? : Array[String] = [],
) -> (String, String) {
  let manifest = if manifest_entries.is_empty() {
    ""
  } else {
    let sorted = manifest_entries.copy()
    sorted.sort_by((a, b) => text_cid(a).compare(text_cid(b)))
    ",\"connector_manifest\":{\"connectors\":[" +
    sorted.join(",") +
    "],\"version\":\"actql-connectors/0.1\"}"
  }
  let head = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[" +
    catalogs.join(",") +
    "]" +
    manifest +
    ",\"contract_registry\":" +
    by_body(contracts)
  let tail = ",\"host_policy_profile\":" +
    host_policy +
    ",\"mapping_contracts\":" +
    by_body(mappings) +
    ",\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":" +
    by_body(views) +
    ",\"version\":\"actql-check-environment/0.1\"}"
  let cid = text_cid(head + tail)
  (head + ",\"evidence_bundle_cid\":\"" + cid + "\"" + tail, cid)
}

///|
fn declaration_limits_for_admission() -> @environment.Limits {
  { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, max_members: 1000, }
}

///|
test "a generated Salesforce declaration passes the existing Check Environment admission" {
  let declaration = salesforce_declaration_fixture()
  let (wire, cid) = declaration_environment(
    [declaration.catalog],
    declaration.contracts,
    declaration.view_bodies,
    salesforce_execution_bodies(declaration),
    manifest_entries=[declaration.manifest_entry],
  )
  // The same chain the existing Catalog fixtures use, through request
  // contracts; this panics on any rejection.
  ignore(query_catalog_from_wire(wire, expected=cid))
  let caps = declaration_limits_for_admission()
  let raw = @environment.read(@utf8.encode(wire), cid, caps).unwrap()
  assert_true(
    @environment.check_mapping_contract_shapes(raw, caps, 1000000) is Ok(_),
  )
  let manifest = @environment.check_connector_manifest(raw, caps).unwrap()
  let entry = @environment.connector_manifest_entry(
    manifest,
    declaration.manifest_entry_cid,
  ).unwrap()
  assert_eq(
    @environment.connector_manifest_entry_identity(entry),
    (declaration.manifest_entry_cid, "salesforce", "crm-main", "salesforce/0.1"),
  )
}

///|
/// Where an environment with these Catalogs, manifest entries and the
/// generated Mappings stops: "read", "mappings", or "admitted".
fn manifest_outcome(
  catalogs : Array[String],
  declaration : @salesforce_catalog.StaticDeclaration,
  entries : Array[String],
) -> String {
  let (wire, cid) = declaration_environment(
    catalogs,
    declaration.contracts,
    declaration.view_bodies,
    salesforce_execution_bodies(declaration),
    manifest_entries=entries,
  )
  let caps = declaration_limits_for_admission()
  match @environment.read(@utf8.encode(wire), cid, caps) {
    Err(InvalidManifest(CatalogMismatch(id))) => "read:CatalogMismatch:" + id
    Err(InvalidManifest(DuplicateConnector(id))) =>
      "read:DuplicateConnector:" + id
    Err(_) => "read"
    Ok(raw) =>
      match @environment.check_mapping_contract_shapes(raw, caps, 1000000) {
        Ok(_) => "admitted"
        Err(ManifestUnresolved(_)) => "mappings:ManifestUnresolved"
        Err(_) => "mappings"
      }
  }
}

///|
test "a generated Mapping must resolve to its connection's manifest entry" {
  let declaration = salesforce_declaration_fixture()
  let catalogs = [declaration.catalog]
  assert_eq(
    manifest_outcome(catalogs, declaration, [declaration.manifest_entry]),
    "admitted",
  )
  // No manifest: the Mapping's reference resolves to nothing.
  assert_true(
    manifest_outcome(catalogs, declaration, []) == "mappings:ManifestUnresolved",
  )
  // A replaced entry (another version) no longer matches the Catalog.
  let replaced = declaration.manifest_entry.replace(
    old="salesforce/0.1",
    new="salesforce/0.2",
  )
  assert_eq(
    manifest_outcome(catalogs, declaration, [replaced]),
    "read:CatalogMismatch:crm-main",
  )
  // Another connection's entry and Catalog: the Mappings do not name it.
  let other = salesforce_declaration_fixture(connector_id="crm-other")
  assert_true(
    manifest_outcome([other.catalog], declaration, [other.manifest_entry]) ==
    "mappings:ManifestUnresolved",
  )
  // An entry without its Catalog, and two entries of one connection id.
  assert_eq(
    manifest_outcome([], declaration, [declaration.manifest_entry]),
    "read:CatalogMismatch:crm-main",
  )
  assert_eq(
    manifest_outcome(catalogs, declaration, [
      declaration.manifest_entry,
      declaration.manifest_entry.replace(
        old="\"salesforce\",",
        new="\"other\",",
      ),
    ]),
    "read:DuplicateConnector:crm-main",
  )
}

///|
test "admission rejects an altered or duplicated Salesforce declaration" {
  let declaration = salesforce_declaration_fixture()
  let caps = declaration_limits_for_admission()
  let mappings = salesforce_execution_bodies(declaration)
  // A declared type changed without resealing no longer matches its CIDs.
  let altered = declaration.catalog.replace(
    old="\"Count__c\":{\"nullable\":true,\"type\":\"number\"}",
    new="\"Count__c\":{\"nullable\":true,\"type\":\"string\"}",
  )
  assert_true(altered != declaration.catalog)
  let (wire, cid) = declaration_environment(
    [altered],
    declaration.contracts,
    declaration.view_bodies,
    mappings,
  )
  let rejected = match @environment.read(@utf8.encode(wire), cid, caps) {
    Err(_) => true
    Ok(raw) =>
      match @environment.check_contract_registry(raw, caps) {
        Err(_) => true
        Ok(registry) =>
          @environment.check_catalog_contents(registry, caps) is Err(_)
      }
  }
  assert_true(rejected)
  // The same logical connection id twice in one environment is refused.
  let (twice, twice_cid) = declaration_environment(
    [declaration.catalog, declaration.catalog],
    declaration.contracts,
    declaration.view_bodies,
    mappings,
  )
  let duplicate = match
    @environment.read(@utf8.encode(twice), twice_cid, caps) {
    Err(_) => true
    Ok(raw) =>
      match @environment.check_contract_registry(raw, caps) {
        Err(_) => true
        Ok(registry) =>
          @environment.check_catalog_contents(registry, caps) is Err(_)
      }
  }
  assert_true(duplicate)
  // Distinct connection ids for the same schema are distinct Catalogs.
  let other = salesforce_declaration_fixture(connector_id="crm-other")
  assert_true(other.catalog_cid != declaration.catalog_cid)
}
