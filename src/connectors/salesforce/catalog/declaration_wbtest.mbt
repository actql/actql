///|
fn declaration_limits() -> DeclarationLimits {
  { max_bytes: 200000, max_nodes: 20000, max_depth: 32, }
}

///|
/// A synthetic Resource covering each declaration decision; no real org.
fn declared_record_describe(
  name_nillable? : Bool = true,
  required_datetime? : Bool = false,
) -> String {
  let fields = [
    "{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false,\"createable\":false,\"updateable\":false,\"sortable\":true}",
    "{\"name\":\"Name\",\"type\":\"string\",\"nillable\":" +
    name_nillable.to_string() +
    ",\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"External_Key__c\",\"type\":\"string\",\"nillable\":false,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true,\"externalId\":true,\"unique\":true,\"caseSensitive\":true}",
    "{\"name\":\"Amount__c\",\"type\":\"double\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"Count__c\",\"type\":\"int\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true,\"filterable\":true}",
    "{\"name\":\"Active__c\",\"type\":\"boolean\",\"nillable\":false,\"defaultedOnCreate\":true,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"Observed_At__c\",\"type\":\"datetime\",\"nillable\":" +
    (!required_datetime).to_string() +
    ",\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"Read_Only__c\",\"type\":\"string\",\"nillable\":true,\"createable\":false,\"updateable\":false}",
    "{\"name\":\"Mystery__c\",\"type\":\"string\",\"createable\":false,\"updateable\":false}",
  ]
  "{\"name\":\"Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true,\"fields\":[" +
  fields.join(",") +
  "]}"
}

///|
fn declared_observation(
  describe : String,
  listing_order? : Array[String] = ["Record__c"],
) -> (CatalogObservation, CatalogObservationBinding) {
  let entries = listing_order.map(name => {
    "{\"name\":\"" +
    name +
    "\",\"queryable\":true,\"createable\":true,\"updateable\":true}"
  })
  let listing = project_resource_listing(
    @utf8.encode("{\"sobjects\":[" + entries.join(",") + "]}"),
    {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 1000,
    },
  ).unwrap()
  let sync = begin_catalog_sync(listing)
  let digests = []
  for name in listing_order {
    let body = if name == "Record__c" {
      describe
    } else {
      "{\"name\":\"" +
      name +
      "\",\"queryable\":true,\"fields\":[{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false}]}"
    }
    catalog_sync_describe(sync, name, @utf8.encode(body), {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 10,
      max_fields: 20,
      max_name_units: 1000,
    }).unwrap()
    digests.push(Some(catalog_response_sha256(@utf8.encode(body))))
  }
  finish_catalog_sync(sync).unwrap()
  let binding = observation_test_binding()
  let observation = prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    listing_order.map(_ => Some("sha256:" + "d".repeat(64))),
    digests,
    100000,
  ).unwrap()
  (observation, binding)
}

///|
fn declared_for(
  describe : String,
  listing_order? : Array[String] = ["Record__c"],
  selection? : Array[String] = ["Record__c"],
) -> StaticDeclaration {
  let (observation, binding) = declared_observation(describe, listing_order~)
  generate_static_declaration(
    observation,
    binding,
    salesforce_implementation("salesforce/0.1").unwrap(),
    "crm-main",
    selection,
    declaration_limits(),
  ).unwrap()
}

///|
test "declaration types each field by an existing exact contract or excludes it" {
  let declaration = declared_for(declared_record_describe())
  assert_eq(declaration.connector_id, "crm-main")
  assert_eq(declaration.connector_version, "salesforce/0.1")
  // Fixed expectations, written independently of the generator.
  assert_eq(declaration.views.length(), 1)
  let view = declaration.views[0]
  assert_eq(view.source_ref, "connector://crm-main/Record__c#records")
  assert_eq(view.fields, [
    "Id", "Name", "External_Key__c", "Count__c", "Active__c", "Read_Only__c",
  ])
  assert_eq(declaration.exclusions, [
    {
      resource: "Record__c",
      field: "Amount__c",
      reason: UnsupportedType("double"),
    },
    {
      resource: "Record__c",
      field: "Observed_At__c",
      reason: UnsupportedType("datetime"),
    },
    {
      resource: "Record__c",
      field: "Mystery__c",
      reason: UnconfirmedNullability,
    },
  ])
  let body = declaration.view_bodies[0]
  assert_true(body.contains("\"view_id\":\"records\""))
  assert_true(body.contains("\"resource_kind\":\"sobject\""))
  assert_true(body.contains("\"operations\":[\"filter\",\"projection\"]"))
  assert_false(body.contains("\"limit\""))
  assert_true(body.contains("\"provider_id_field\":\"Id\""))
  let catalog = declaration.catalog
  assert_true(
    catalog.contains("\"Count__c\":{\"nullable\":true,\"type\":\"number\"}"),
  )
  assert_true(
    catalog.contains("\"Active__c\":{\"nullable\":false,\"type\":\"boolean\"}"),
  )
  assert_true(
    catalog.contains("\"Id\":{\"nullable\":false,\"type\":\"string\"}"),
  )
  assert_false(catalog.contains("Amount__c"))
  assert_false(catalog.contains("Observed_At__c"))
  assert_true(catalog.contains("\"commands\":[]"))
}

///|
test "declaration writes only what this revision can execute" {
  let declaration = declared_for(declared_record_describe())
  assert_eq(declaration.mappings.length(), 1)
  let mapping = declaration.mappings[0]
  assert_eq(mapping.mapping_ref, "mapping:crm-main/Record__c.v1")
  assert_eq(mapping.target_ref, "connector://crm-main/Record__c")
  let writable = ["Active__c", "Count__c", "External_Key__c", "Name"]
  assert_eq(mapping.create_fields, Some(writable))
  assert_eq(mapping.update_fields, Some(writable))
  assert_eq(mapping.upsert_fields, Some(writable))
  assert_eq(mapping.upsert_keys, ["External_Key__c"])
  // A defaulted or nullable field is not required; the external ID is.
  assert_true(
    mapping.body.contains("\"required_fields\":[\"External_Key__c\"]"),
  )
  assert_true(mapping.body.contains("\"row_mapping\":{}"))
  assert_true(mapping.body.contains("\"selector_class\":\"key\""))
  assert_false(mapping.body.contains("\"delete\""))
  assert_false(mapping.body.contains("Amount__c"))
  assert_true(
    mapping.body.contains(
      "\"connector_manifest_cid\":\"" + declaration.catalog_cid + "\"",
    ),
  )
}

///|
test "an unwritable required field withholds create and upsert only" {
  let declaration = declared_for(
    declared_record_describe(required_datetime=true),
  )
  let mapping = declaration.mappings[0]
  assert_eq(mapping.create_fields, None)
  assert_eq(mapping.upsert_fields, None)
  assert_true(mapping.update_fields is Some(_))
  assert_true(
    declaration.exclusions.contains({
      resource: "Record__c",
      field: "Observed_At__c",
      reason: CreateRequirementUnknown("Observed_At__c"),
    }),
  )
}

///|
test "declaration identity ignores enumeration order and follows meaning" {
  let first = declared_for(declared_record_describe(), listing_order=[
    "Record__c", "Other__c",
  ])
  let second = declared_for(declared_record_describe(), listing_order=[
    "Other__c", "Record__c",
  ])
  assert_eq(first.catalog_cid, second.catalog_cid)
  assert_eq(first.catalog, second.catalog)
  let both = declared_for(
    declared_record_describe(),
    listing_order=["Other__c", "Record__c"],
    selection=["Record__c", "Other__c"],
  )
  let reversed = declared_for(
    declared_record_describe(),
    listing_order=["Record__c", "Other__c"],
    selection=["Other__c", "Record__c"],
  )
  assert_eq(both.catalog_cid, reversed.catalog_cid)
  assert_eq(both.views.length(), 2)
  // A meaningful change (nullability) changes the identity.
  let changed = declared_for(declared_record_describe(name_nillable=false))
  assert_true(changed.catalog_cid != first.catalog_cid)
}

///|
test "declaration refuses foreign revisions, invalid ids and unseen Resources" {
  let (observation, binding) = declared_observation(declared_record_describe())
  let implementation = salesforce_implementation("salesforce/0.1").unwrap()
  assert_true(salesforce_implementation("salesforce/9.9") is None)
  assert_true(
    generate_static_declaration(
      observation,
      { ..binding, connector_revision: "salesforce/9.9", },
      implementation,
      "crm-main",
      ["Record__c"],
      declaration_limits(),
    )
    is Err(ForeignImplementation),
  )
  for id in ["", "/x", "a//b", "a#b", "a:b", "x/"] {
    assert_true(
      generate_static_declaration(
        observation,
        binding,
        implementation,
        id,
        ["Record__c"],
        declaration_limits(),
      )
      is Err(InvalidConnectorId),
    )
  }
  assert_true(
    generate_static_declaration(
      observation,
      binding,
      implementation,
      "crm-main",
      ["Record__c", "Record__c"],
      declaration_limits(),
    )
    is Err(InvalidSelection),
  )
  // A Resource outside the observation is not declared absent: it fails.
  assert_true(
    generate_static_declaration(
      observation,
      binding,
      implementation,
      "crm-main",
      ["Unseen__c"],
      declaration_limits(),
    )
    is Err(Observation(_)),
  )
}

///|
test "declared use is checked before I/O against the Site and the rules" {
  let (observation, binding) = declared_observation(declared_record_describe())
  let declaration = declared_for(declared_record_describe())
  let create = prepare_write_projection(
    observation,
    binding,
    "Record__c",
    WriteCreate,
    ["External_Key__c", "Name"],
    8,
  ).unwrap()
  assert_true(check_declared_write(declaration, create) is Ok(_))
  let decimal = prepare_write_projection(
    observation,
    binding,
    "Record__c",
    WriteCreate,
    ["External_Key__c", "Amount__c"],
    8,
  ).unwrap()
  assert_eq(
    check_declared_write(declaration, decimal),
    Err(UndeclaredField("Amount__c")),
  )
  let upsert = prepare_write_projection(
    observation,
    binding,
    "Record__c",
    WriteUpsertByExternalId("External_Key__c"),
    ["Name"],
    8,
  ).unwrap()
  assert_true(check_declared_write(declaration, upsert) is Ok(_))
  // Another Site generation or org is refused even with the same names.
  let foreign = { ..create, binding: { ..binding, site_generation: 5, }, }
  assert_eq(check_declared_write(declaration, foreign), Err(ForeignDeclaration))
  let other_org = {
    ..create,
    binding: { ..binding, org_id: "00D000000000002EAA", },
  }
  assert_eq(
    check_declared_write(declaration, other_org),
    Err(ForeignDeclaration),
  )
  // A later sync of the same Site is accepted: only the dispatch differs.
  let later = {
    ..create,
    binding: {
      ..binding,
      dispatch_request_cid: "sha256:" + "e".repeat(64),
      sync_occurrence: "sync-b",
    },
  }
  assert_true(check_declared_write(declaration, later) is Ok(_))
  // Read side has its own check.
  let view = declaration.views[0].view_cid
  let read = prepare_read_projection(
    observation,
    binding,
    "Record__c",
    ["Id", "Count__c"],
    4096,
  ).unwrap()
  assert_true(check_declared_read(declaration, read, view) is Ok(_))
  assert_eq(
    check_declared_read(declaration, read, "sha256:" + "0".repeat(64)),
    Err(Undeclared),
  )
  let blocked = declared_for(declared_record_describe(required_datetime=true))
  assert_eq(check_declared_write(blocked, create), Err(Undeclared))
}
