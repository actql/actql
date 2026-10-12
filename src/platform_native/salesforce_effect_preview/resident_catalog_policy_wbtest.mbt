///|
/// Independent metadata values; these tests compose existing Catalog and
/// checked Mapping Owners, not physical Provider reads or public approval.
fn catalog_policy_test_observation(
  binding : @catalog.CatalogObservationBinding,
  count_type? : String = "int",
) -> @catalog.CatalogObservation {
  let response : @resource.NativeCredentialResponse = {
    use_cid: "sha256:" + "d".repeat(64),
    status: 200,
    body: @utf8.encode(
      "{\"name\":\"ActQL_Test_Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true,\"fields\":[{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false,\"createable\":false,\"updateable\":false},{\"name\":\"Count__c\",\"type\":\"" +
      count_type +
      "\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}]}",
    ),
  }
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

///|
fn catalog_policy_test_limits() -> @catalog.DeclarationLimits {
  { max_bytes: 65536, max_nodes: 4096, max_depth: 32, }
}

///|
fn catalog_policy_test_mapping(
  catalog : @catalog.CatalogObservation,
) -> @catalog.ExecutionMapping {
  let binding = match catalog.binding {
    @catalog.SiteCatalog(original) => original
    @catalog.DirectLocalCatalog(_) => abort("Site Catalog fixture required")
  }
  let declaration = @catalog.generate_static_declaration(
    catalog,
    binding,
    @catalog.salesforce_implementation("salesforce/0.1").unwrap(),
    "crm",
    ["ActQL_Test_Record__c"],
    catalog_policy_test_limits(),
  ).unwrap()
  @catalog.prepare_execution_mapping(
    declaration,
    "ActQL_Test_Record__c",
    @catalog.CreateFromResult([
      { target: "Count__c", source: "id", null_behavior: "reject", },
    ]),
    catalog_policy_test_limits(),
  ).unwrap()
}

///|
/// Check the original authoring environment through its actual Owner. This
/// factory's generated Mapping is the original authoring input, not an
/// expected result vector or a substitute for an issued Run/material custody.
fn catalog_policy_test_checked_shape(
  mapping : @catalog.ExecutionMapping,
  body? : String? = None,
) -> @environment.MappingContractShape {
  let declaration = mapping.declaration
  let contracts = declaration.contracts.copy()
  contracts.sort_by((a, b) => {
    @sha.hex(@utf8.encode(a)).compare(@sha.hex(@utf8.encode(b)))
  })
  let before = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[" +
    declaration.catalog +
    "],\"connector_manifest\":{\"connectors\":[" +
    declaration.manifest_entry +
    "],\"version\":\"actql-connectors/0.1\"},\"contract_registry\":[" +
    contracts.join(",") +
    "]"
  let after = ",\"host_policy_profile\":{},\"mapping_contracts\":[" +
    body.unwrap_or(mapping.body) +
    "],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(before + after))
  let limits : @environment.Limits = {
    max_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
    max_members: 100,
  }
  let environment = @environment.read(
    @utf8.encode(before + ",\"evidence_bundle_cid\":\"" + cid + "\"" + after),
    cid,
    limits,
  ).unwrap()
  let shapes = @environment.check_mapping_contract_shapes(
    environment, limits, 1000,
  ).unwrap()
  @environment.mapping_shape_at(shapes, 0).unwrap()
}

///|
test "original Catalog policy preserves the checked result-backed create Mapping and projection" {
  let binding = named_catalog_test_binding()
  let catalog = catalog_policy_test_observation(binding)
  let original_mapping = catalog_policy_test_mapping(catalog)
  let original = catalog_policy_test_checked_shape(original_mapping)
  let (mapping, projection) = native_resident_create_mapping_from_shape(
    original,
    catalog,
    binding,
    "crm",
    "ActQL_Test_Record__c",
    catalog_policy_test_limits(),
    2,
    1000,
  ).unwrap()
  assert_eq(mapping.mapping_ref, original_mapping.mapping_ref)
  assert_eq(mapping.mapping_cid, @environment.mapping_shape_cid(original))
  assert_eq(mapping.operation, @catalog.WriteCreate)
  assert_eq(mapping.fields, ["Count__c"])
  assert_true(@catalog.check_execution_write(mapping, projection) is Ok(_))
}

///|
test "original Catalog policy refuses foreign Run dispatch Site and generation without replacing expected scope" {
  let binding = named_catalog_test_binding()
  let original = catalog_policy_test_checked_shape(
    catalog_policy_test_mapping(catalog_policy_test_observation(binding)),
  )
  for
    foreign in [
      { ..binding, run_invocation_cid: "sha256:" + "e".repeat(64), },
      { ..binding, dispatch_request_cid: "sha256:" + "e".repeat(64), },
      { ..binding, site_key: "foreign-site", },
      { ..binding, site_generation: 5, },
    ] {
    assert_true(
      native_resident_create_mapping_from_shape(
        original,
        catalog_policy_test_observation(foreign),
        binding,
        "crm",
        "ActQL_Test_Record__c",
        catalog_policy_test_limits(),
        2,
        1000,
      )
      is Err(OriginalScopeMismatch),
    )
  }
}

///|
test "original Catalog policy rejects changed carrier type and Connector identity despite matching field names" {
  let binding = named_catalog_test_binding()
  let catalog = catalog_policy_test_observation(binding)
  let original = catalog_policy_test_checked_shape(
    catalog_policy_test_mapping(catalog),
  )
  assert_true(
    native_resident_create_mapping_from_shape(
      original,
      catalog_policy_test_observation(binding, count_type="string"),
      binding,
      "crm",
      "ActQL_Test_Record__c",
      catalog_policy_test_limits(),
      2,
      1000,
    )
    is Err(OriginalMappingMismatch),
  )
  assert_true(
    native_resident_create_mapping_from_shape(
      original,
      catalog,
      binding,
      "foreign-crm",
      "ActQL_Test_Record__c",
      catalog_policy_test_limits(),
      2,
      1000,
    )
    is Err(OriginalMappingMismatch),
  )
}

///|
test "original Catalog policy rejects limits before deriving a replacement Mapping" {
  let binding = named_catalog_test_binding()
  let catalog = catalog_policy_test_observation(binding)
  let original = catalog_policy_test_checked_shape(
    catalog_policy_test_mapping(catalog),
  )
  assert_true(
    native_resident_create_mapping_from_shape(
      original,
      catalog,
      binding,
      "crm",
      "ActQL_Test_Record__c",
      catalog_policy_test_limits(),
      0,
      1000,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    native_resident_create_mapping_from_shape(
      original,
      catalog,
      binding,
      "crm",
      "ActQL_Test_Record__c",
      catalog_policy_test_limits(),
      2,
      0,
    )
    is Err(InvalidLimits),
  )
}

///|
test "original Catalog policy refuses unsupported literal mapping rather than converting it to a Result field" {
  let binding = named_catalog_test_binding()
  let catalog = catalog_policy_test_observation(binding)
  let mapping = catalog_policy_test_mapping(catalog)
  let preimage = mapping.body
    .replace(
      old="\"mapping_contract_cid\":\"" + mapping.mapping_cid + "\",",
      new="",
    )
    .replace(
      old="{\"field\":\"id\",\"null_behavior\":\"reject\"}",
      new="{\"literal\":3,\"null_behavior\":\"reject\"}",
    )
  let cid = "sha256:" + @sha.hex(@utf8.encode(preimage))
  let body = preimage.replace(
    old="\"mapping_ref\":",
    new="\"mapping_contract_cid\":\"" + cid + "\",\"mapping_ref\":",
  )
  let original = catalog_policy_test_checked_shape(mapping, body=Some(body))
  assert_true(
    native_resident_create_mapping_from_shape(
      original,
      catalog,
      binding,
      "crm",
      "ActQL_Test_Record__c",
      catalog_policy_test_limits(),
      2,
      1000,
    )
    is Err(UnsupportedWrite),
  )
}
