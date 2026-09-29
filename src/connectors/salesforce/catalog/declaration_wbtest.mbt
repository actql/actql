///|
fn declaration_limits() -> DeclarationLimits {
  { max_bytes: 200000, max_nodes: 20000, max_depth: 32, }
}

///|
/// A synthetic Resource covering each declaration decision; no real org.
fn declared_record_describe(
  name_nillable? : Bool = true,
  required_time? : Bool = false,
) -> String {
  let fields = [
    "{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false,\"createable\":false,\"updateable\":false,\"sortable\":true}",
    "{\"name\":\"Name\",\"type\":\"string\",\"nillable\":" +
    name_nillable.to_string() +
    ",\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"External_Key__c\",\"type\":\"string\",\"nillable\":false,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true,\"externalId\":true,\"unique\":true,\"caseSensitive\":true}",
    "{\"name\":\"Amount__c\",\"type\":\"double\",\"precision\":16,\"scale\":2,\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"Unit_Price__c\",\"type\":\"double\",\"precision\":15,\"scale\":2,\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"Count__c\",\"type\":\"int\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true,\"filterable\":true}",
    "{\"name\":\"Active__c\",\"type\":\"boolean\",\"nillable\":false,\"defaultedOnCreate\":true,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"Observed_At__c\",\"type\":\"datetime\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"Due_On__c\",\"type\":\"date\",\"nillable\":false,\"defaultedOnCreate\":true,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"Opens_At__c\",\"type\":\"time\",\"nillable\":" +
    (!required_time).to_string() +
    ",\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"Rate__c\",\"type\":\"percent\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}",
    "{\"name\":\"Price__c\",\"type\":\"currency\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}",
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
    "Id", "Name", "External_Key__c", "Unit_Price__c", "Count__c", "Active__c", "Observed_At__c",
    "Due_On__c", "Read_Only__c",
  ])
  // A Number above precision 15 is not recovered exactly from its reply;
  // `percent`, `currency` and `time` have no exact existing contract.
  assert_eq(declaration.exclusions, [
    {
      resource: "Record__c",
      field: "Amount__c",
      reason: UnsupportedPrecision(Some(16), Some(2)),
    },
    {
      resource: "Record__c",
      field: "Opens_At__c",
      reason: UnsupportedType("time"),
    },
    {
      resource: "Record__c",
      field: "Rate__c",
      reason: UnsupportedType("percent"),
    },
    {
      resource: "Record__c",
      field: "Price__c",
      reason: UnsupportedType("currency"),
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
  // A Salesforce `date` is an ActQL date; a `datetime` is a timestamp.
  assert_true(
    catalog.contains(
      "\"Observed_At__c\":{\"nullable\":true,\"type\":\"timestamp\"}",
    ),
  )
  assert_true(
    catalog.contains("\"Due_On__c\":{\"nullable\":false,\"type\":\"date\"}"),
  )
  // A Number up to precision 15 is its described decimal.
  assert_true(
    catalog.contains(
      "\"Unit_Price__c\":{\"nullable\":true,\"precision\":15,\"scale\":2,\"type\":\"decimal\"}",
    ),
  )
  let json = static_declaration_json(declaration, declaration_limits()).unwrap()
  assert_true(
    json.contains(
      "{\"field\":\"Amount__c\",\"reason\":{\"kind\":\"unsupported_precision\",\"native_type\":\"double\",\"precision\":16,\"scale\":2},\"resource\":\"Record__c\"}",
    ),
  )
  for name in ["Amount__c", "Opens_At__c", "Rate__c", "Price__c"] {
    assert_false(catalog.contains("\"" + name + "\""))
  }
  assert_true(catalog.contains("\"commands\":[]"))
}

///|
test "declaration lists writable fields per operation, not a Mapping" {
  let declaration = declared_for(declared_record_describe())
  assert_eq(declaration.writables.length(), 1)
  let writable = declaration.writables[0]
  assert_eq(writable.target_ref, "connector://crm-main/Record__c")
  let fields = [
    "Active__c", "Count__c", "Due_On__c", "External_Key__c", "Name", "Observed_At__c",
    "Unit_Price__c",
  ]
  assert_eq(writable.create_fields, Some(fields))
  assert_eq(writable.update_fields, Some(fields))
  assert_eq(writable.upsert_fields, Some(fields))
  assert_eq(writable.upsert_keys, ["External_Key__c"])
  // A defaulted or nullable field is not required; the external ID is.
  assert_eq(writable.required_fields, ["External_Key__c"])
  // A written datetime is whole seconds only, and the declaration says so.
  assert_eq(writable.timestamp_whole_seconds, ["Observed_At__c"])
  let json = static_declaration_json(declaration, declaration_limits()).unwrap()
  assert_true(json.contains("\"timestamp_whole_seconds\":[\"Observed_At__c\"]"))
}

///|
test "an unwritable required field withholds create and upsert only" {
  let declaration = declared_for(declared_record_describe(required_time=true))
  let writable = declaration.writables[0]
  assert_eq(writable.create_fields, None)
  assert_eq(writable.upsert_fields, None)
  assert_true(writable.update_fields is Some(_))
  assert_true(
    declaration.exclusions.contains({
      resource: "Record__c",
      field: "Opens_At__c",
      reason: CreateRequirementUnknown("Opens_At__c"),
    }),
  )
}

///|
/// Computed independently with the repository's JavaScript canonical JSON
/// from {"connector":"salesforce","connector_id":"crm-main",
/// "connector_version":"salesforce/0.1"}.
fn manifest_entry_cid_fixture() -> String {
  "sha256:7904bd9ee967d1e25402eadc6e666e0c8e83e6f5614df37327868bae73f62695"
}

///|
fn execution(
  declaration : StaticDeclaration,
  write : ExecutionWrite,
) -> Result[ExecutionMapping, ExecutionMappingIssue] {
  prepare_execution_mapping(
    declaration,
    "Record__c",
    write,
    declaration_limits(),
  )
}

///|
test "an execution Mapping is exactly one write the provider accepts" {
  let declaration = declared_for(declared_record_describe())
  // Update of Name only: one rule with exactly [Name].
  let update = execution(declaration, UpdateById(["Name"])).unwrap()
  assert_true(
    update.mapping_ref.has_prefix("mapping:crm-main/Record__c/update-"),
  )
  assert_true(update.mapping_ref.has_suffix(".v1"))
  assert_true(
    update.body.contains(
      "\"permission_rules\":[{\"effect_kind\":\"update\",\"permissions\":[\"salesforce:record:update\"],\"selector_class\":\"id\",\"write_fields\":[\"Name\"]}]",
    ),
  )
  assert_true(update.body.contains("\"writable_fields\":[\"Name\"]"))
  assert_true(update.body.contains("\"required_fields\":[]"))
  assert_true(update.body.contains("\"row_mapping\":{}"))
  assert_true(
    update.body.contains(
      "\"connector_manifest_cid\":\"" + manifest_entry_cid_fixture() + "\"",
    ),
  )
  assert_false(update.body.contains(declaration.catalog_cid))
  // Upsert on the external ID: the key selects and is not a body field, but
  // is part of the target schema.
  let upsert = execution(
    declaration,
    UpsertByExternalId("External_Key__c", ["Name"]),
  ).unwrap()
  assert_true(
    upsert.body.contains(
      "\"selector_class\":\"key\",\"write_fields\":[\"Name\"]",
    ),
  )
  assert_true(
    upsert.body.contains(
      "\"External_Key__c\":{\"nullable\":false,\"type\":\"string\"}",
    ),
  )
  assert_true(
    execution(
      declaration,
      UpsertByExternalId("External_Key__c", ["External_Key__c", "Name"]),
    )
    is Err(KeyInBody("External_Key__c")),
  )
  assert_true(
    execution(declaration, UpsertByExternalId("Name", ["Count__c"]))
    is Err(KeyNotDeclared("Name")),
  )
  // Create from a Named Result maps each target from a source field.
  let create = execution(
    declaration,
    CreateFromResult([
      { target: "External_Key__c", source: "key", null_behavior: "reject", },
      { target: "Name", source: "label", null_behavior: "write_null", },
    ]),
  ).unwrap()
  assert_true(
    create.body.contains(
      "\"row_mapping\":{\"External_Key__c\":{\"field\":\"key\",\"null_behavior\":\"reject\"},\"Name\":{\"field\":\"label\",\"null_behavior\":\"write_null\"}}",
    ),
  )
  assert_true(create.body.contains("\"required_fields\":[\"External_Key__c\"]"))
  assert_true(
    execution(
      declaration,
      CreateFromResult([
        { target: "Name", source: "label", null_behavior: "reject", },
      ]),
    )
    is Err(MissingRequiredField("External_Key__c")),
  )
  assert_true(
    execution(
      declaration,
      CreateFromResult([
        { target: "External_Key__c", source: "key", null_behavior: "omit", },
      ]),
    )
    is Err(InvalidNullBehavior("External_Key__c")),
  )
  assert_true(
    execution(
      declaration,
      CreateFromResult([
        {
          target: "External_Key__c",
          source: "key",
          null_behavior: "write_null",
        },
      ]),
    )
    is Err(InvalidNullBehavior("External_Key__c")),
  )
  assert_true(
    execution(declaration, CreatePayload(["External_Key__c", "Amount__c"]))
    is Err(FieldNotWritable("Amount__c")),
  )
  assert_true(execution(declaration, UpdateById([])) is Err(EmptyWrite))
  assert_true(
    execution(declaration, UpdateById(["Name", "Name"]))
    is Err(DuplicateField("Name")),
  )
  // The manifest entry is this connection's, derived from the declaration.
  assert_eq(declaration.manifest_entry_cid, manifest_entry_cid_fixture())
  assert_eq(
    declaration.manifest_entry,
    "{\"connector\":\"salesforce\",\"connector_id\":\"crm-main\",\"connector_version\":\"salesforce/0.1\"}",
  )
  // Distinct writes have distinct references; the same write is stable.
  let again = execution(declaration, UpdateById(["Name"])).unwrap()
  assert_eq(again.mapping_cid, update.mapping_cid)
  let wider = execution(declaration, UpdateById(["Count__c", "Name"])).unwrap()
  assert_true(wider.mapping_ref != update.mapping_ref)
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
  let update = execution(declaration, UpdateById(["Name"])).unwrap()
  let projection = (operation, fields) => {
    prepare_write_projection(
      observation, binding, "Record__c", operation, fields, 8,
    ).unwrap()
  }
  assert_true(
    check_execution_write(update, projection(WriteUpdateById, ["Name"]))
    is Ok(_),
  )
  // Exactly the Mapping's fields: neither more nor fewer.
  assert_eq(
    check_execution_write(
      update,
      projection(WriteUpdateById, ["Name", "Count__c"]),
    ),
    Err(UndeclaredField("Count__c")),
  )
  let wider = execution(declaration, UpdateById(["Count__c", "Name"])).unwrap()
  assert_eq(
    check_execution_write(wider, projection(WriteUpdateById, ["Name"])),
    Err(Undeclared),
  )
  assert_eq(
    check_execution_write(
      update,
      projection(WriteCreate, ["External_Key__c", "Name"]),
    ),
    Err(Undeclared),
  )
  let upsert = execution(
    declaration,
    UpsertByExternalId("External_Key__c", ["Name"]),
  ).unwrap()
  assert_true(
    check_execution_write(
      upsert,
      projection(WriteUpsertByExternalId("External_Key__c"), ["Name"]),
    )
    is Ok(_),
  )
  // Another Site generation or org is refused even with the same names.
  let current = projection(WriteUpdateById, ["Name"])
  assert_eq(
    check_execution_write(update, {
      ..current,
      binding: { ..binding, site_generation: 5, },
    }),
    Err(ForeignDeclaration),
  )
  assert_eq(
    check_execution_write(update, {
      ..current,
      binding: { ..binding, org_id: "00D000000000002EAA", },
    }),
    Err(ForeignDeclaration),
  )
  // A later sync of the same Site is accepted: only the dispatch differs.
  assert_true(
    check_execution_write(update, {
      ..current,
      binding: {
        ..binding,
        dispatch_request_cid: "sha256:" + "e".repeat(64),
        sync_occurrence: "sync-b",
      },
    })
    is Ok(_),
  )
  // Same Site, changed schema: a projection from the new describe is
  // refused until the Resource is declared again.
  let (changed, _) = declared_observation(
    declared_record_describe(name_nillable=false),
  )
  let drifted = prepare_write_projection(
    changed,
    binding,
    "Record__c",
    WriteUpdateById,
    ["Name"],
    8,
  ).unwrap()
  assert_eq(check_execution_write(update, drifted), Err(SchemaChanged("Name")))
  let (unkeyed, _) = declared_observation(
    declared_record_describe().replace(
      old="\"externalId\":true,\"unique\":true,\"caseSensitive\":true",
      new="\"externalId\":true,\"unique\":true,\"caseSensitive\":false",
    ),
  )
  let rekeyed = prepare_write_projection(
    unkeyed,
    binding,
    "Record__c",
    WriteUpsertByExternalId("External_Key__c"),
    ["Name"],
    8,
  ).unwrap()
  assert_eq(
    check_execution_write(upsert, rekeyed),
    Err(SchemaChanged("External_Key__c")),
  )
  // Read side has its own check, including the field meaning.
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
  let drifted_read = prepare_read_projection(
    changed,
    binding,
    "Record__c",
    ["Id", "Name"],
    4096,
  ).unwrap()
  assert_eq(
    check_declared_read(declaration, drifted_read, view),
    Err(SchemaChanged("Name")),
  )
}

///|
test "an omitted null source is the only field a row may leave out" {
  let (observation, binding) = declared_observation(declared_record_describe())
  let declaration = declared_for(declared_record_describe())
  let create = execution(
    declaration,
    CreateFromResult([
      { target: "External_Key__c", source: "key", null_behavior: "reject", },
      { target: "Name", source: "label", null_behavior: "omit", },
    ]),
  ).unwrap()
  assert_true(create.body.contains("\"null_behavior\":\"omit\""))
  let projection = prepare_write_projection(
    observation,
    binding,
    "Record__c",
    WriteCreate,
    ["External_Key__c", "Name"],
    8,
  ).unwrap()
  let limits : WriteBodyLimits = {
    max_bytes: 1024,
    max_nodes: 32,
    max_depth: 5,
  }
  let row = text => {
    prepare_execution_write_body(create, projection, @utf8.encode(text), limits)
  }
  // A null label was omitted by the Mapping; a present one is written.
  let omitted = row("{\"External_Key__c\":\"k1\"}").unwrap()
  assert_eq(write_body_json(omitted), "{\"External_Key__c\":\"k1\"}")
  let written = row("{\"External_Key__c\":\"k2\",\"Name\":\"two\"}").unwrap()
  assert_eq(
    write_body_json(written),
    "{\"External_Key__c\":\"k2\",\"Name\":\"two\"}",
  )
  // A rejected (required) source is never omitted.
  assert_true(row("{\"Name\":\"two\"}") is Err(MissingField("External_Key__c")))
  // Without the Mapping, the exact projection still requires every field.
  assert_true(
    prepare_write_body(
      projection,
      @utf8.encode("{\"External_Key__c\":\"k1\"}"),
      limits,
    )
    is Err(MissingField("Name")),
  )
  // Per-row check before I/O: omission only where the Mapping omits.
  assert_true(
    check_execution_write(create, projection, bodies=[
      write_body_json(omitted),
      write_body_json(written),
    ])
    is Ok(_),
  )
  let rejecting = execution(
    declaration,
    CreateFromResult([
      { target: "External_Key__c", source: "key", null_behavior: "reject", },
      { target: "Name", source: "label", null_behavior: "reject", },
    ]),
  ).unwrap()
  assert_eq(
    check_execution_write(rejecting, projection, bodies=[
      write_body_json(omitted),
    ]),
    Err(OmittedField("Name")),
  )
}
