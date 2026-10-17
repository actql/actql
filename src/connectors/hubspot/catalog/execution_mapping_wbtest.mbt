///|
fn mapping_limits() -> MappingLimits {
  {
    max_properties: 100,
    max_fields: 20,
    max_name_bytes: 256,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }
}

///|
fn mapping_catalog() -> PropertyCatalog {
  catalog(
    (
      #|{"results":[{"name":"amount","type":"number","fieldType":"number","calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"tags","type":"enumeration","fieldType":"checkbox","options":[{"value":"a"},{"value":"b"}],"calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"external_key","type":"string","fieldType":"text","hasUniqueValue":true,"calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"domain","type":"string","fieldType":"text","hasUniqueValue":false},{"name":"computed","type":"number","fieldType":"number","calculated":true,"modificationMetadata":{"readOnlyValue":true}}]}
    ),
  )
}

///|
fn mapping_manifest() -> String {
  "sha256:" + "a".repeat(64)
}

///|
fn mapped(operation : RecordWriteOperation) -> ExecutionMapping {
  prepare_execution_mapping(
    mapping_catalog(),
    "hubspot",
    mapping_manifest(),
    "companies",
    operation,
    ["tags", "amount"],
    if operation is Create {
      [
        { target: "tags", field: "tags", null_behavior: "reject", },
        { target: "amount", field: "amount", null_behavior: "omit", },
      ]
    } else {
      []
    },
    mapping_limits(),
  ).unwrap()
}

///|
test "execution mappings retain full decimal and array contracts with operation-specific rules" {
  for operation in [Create, Update, Upsert("external_key")] {
    let mapping = mapped(operation)
    let wire = execution_mapping_body(mapping)
    assert_true(wire.contains("\"precision\":38"))
    assert_true(wire.contains("\"scale\":10"))
    assert_true(wire.contains("\"type\":\"array\""))
    assert_true(
      wire.contains("\"connector_manifest_cid\":\"" + mapping_manifest() + "\""),
    )
    assert_eq(execution_mapping_fields(mapping), ["amount", "tags"])
    assert_true(mapping.mapping_cid.has_prefix("sha256:"))
    if operation is Upsert(_) {
      assert_true(wire.contains("\"external_key\""))
      assert_true(wire.contains("\"selector_class\":\"key\""))
    }
  }
  assert_true(mapped(Create).mapping_cid != mapped(Update).mapping_cid)
  assert_true(
    mapped(Update).mapping_cid != mapped(Upsert("external_key")).mapping_cid,
  )
}

///|
test "mapping derivation keeps field order canonical and copies selected inputs" {
  let fields = ["tags", "amount"]
  let sources = [
    { target: "tags", field: "tags", null_behavior: "reject", },
    { target: "amount", field: "amount", null_behavior: "omit", },
  ]
  let original = prepare_execution_mapping(
    mapping_catalog(),
    "hubspot",
    mapping_manifest(),
    "companies",
    Create,
    fields,
    sources,
    mapping_limits(),
  ).unwrap()
  fields[0] = "computed"
  sources.clear()
  let returned = execution_mapping_fields(original)
  returned[0] = "domain"
  assert_eq(original.mapping_cid, mapped(Create).mapping_cid)
  assert_eq(
    execution_mapping_body(original),
    execution_mapping_body(mapped(Create)),
  )
}

///|
test "mapping refuses unconfirmed writes and unproven domain keys while preserving unique upsert" {
  for name in ["computed", "domain", "id"] {
    assert_true(
      prepare_execution_mapping(
        mapping_catalog(),
        "hubspot",
        mapping_manifest(),
        "companies",
        Update,
        [name],
        [],
        mapping_limits(),
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_execution_mapping(
      mapping_catalog(),
      "hubspot",
      mapping_manifest(),
      "companies",
      Upsert("domain"),
      ["amount"],
      [],
      mapping_limits(),
    )
    is Err(Property(UniqueKeyUnconfirmed("domain"))),
  )
  assert_true(
    prepare_execution_mapping(
      mapping_catalog(),
      "hubspot",
      mapping_manifest(),
      "companies",
      Upsert("external_key"),
      ["amount"],
      [],
      mapping_limits(),
    )
    is Ok(_),
  )
}

///|
test "mapped bodies preserve exact values and only original explicit omission" {
  let mapping = mapped(Create)
  let body = prepare_execution_write_body(
    mapping,
    mapping_catalog(),
    b"{\"tags\":[\"a\",\"b\"]}",
    100,
    write_limits(),
  ).unwrap()
  assert_eq(write_body_properties_json(body), "{\"tags\":\"a;b\"}")
  assert_eq(write_body_value_json(body), "{\"tags\":[\"a\",\"b\"]}")
  let body = prepare_execution_write_body(
    mapping,
    mapping_catalog(),
    b"{\"amount\":\"9007199254740993.0100000000\",\"tags\":[\"a\",\"b\"]}",
    100,
    write_limits(),
  ).unwrap()
  assert_eq(
    write_body_value_json(body),
    "{\"amount\":\"9007199254740993.0100000000\",\"tags\":[\"a\",\"b\"]}",
  )
  assert_true(
    prepare_execution_write_body(
      mapping,
      mapping_catalog(),
      b"{\"amount\":null}",
      100,
      write_limits(),
    )
    is Err(Body(MissingField("tags"))),
  )
  assert_true(
    prepare_execution_write_body(
      mapping,
      mapping_catalog(),
      b"{\"tags\":[\"a\"],\"extra\":0}",
      100,
      write_limits(),
    )
    is Err(Body(UnexpectedField("extra"))),
  )
  assert_true(
    prepare_execution_write_body(
      mapped(Update),
      mapping_catalog(),
      b"{\"tags\":[\"a\"]}",
      100,
      write_limits(),
    )
    is Err(Body(MissingField("amount"))),
  )
}

///|
test "mapped current body cannot substitute changed metadata or another object" {
  let original = mapped(Update)
  let changed = catalog(
    (
      #|{"results":[{"name":"amount","type":"string","fieldType":"text"}]}
    ),
  )
  assert_true(
    recheck_execution_mapping(original, changed, 100) is Err(ForeignCatalog),
  )
  assert_true(
    prepare_execution_write_body(original, changed, b"{}", 100, write_limits())
    is Err(Property(ForeignCatalog)),
  )
}

///|
test "invalid mapping bindings sources duplicates and output ceilings cannot yield a partial mapping" {
  let cat = mapping_catalog()
  for
    sources in [
      [],
      [{ target: "amount", field: "x", null_behavior: "default", }],
      [{ target: "amount", field: "", null_behavior: "reject", }],
    ] {
    assert_true(
      prepare_execution_mapping(
        cat,
        "hubspot",
        mapping_manifest(),
        "companies",
        Create,
        ["amount"],
        sources,
        mapping_limits(),
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_execution_mapping(
      cat,
      "hubspot",
      "not-a-cid",
      "companies",
      Update,
      ["amount"],
      [],
      mapping_limits(),
    )
    is Err(InvalidBinding),
  )
  assert_true(
    prepare_execution_mapping(
      cat,
      "hubspot",
      mapping_manifest(),
      "companies",
      Update,
      ["amount", "amount"],
      [],
      mapping_limits(),
    )
    is Err(DuplicateField("amount")),
  )
  assert_true(
    prepare_execution_mapping(
      cat,
      "hubspot",
      mapping_manifest(),
      "companies",
      Update,
      ["amount"],
      [],
      { ..mapping_limits(), max_bytes: 32, },
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_execution_write_body(mapped(Create), cat, b"{}", 100, {
      ..write_limits(),
      max_input_bytes: 0,
    })
    is Err(Body(InvalidLimits)),
  )
  assert_true(
    prepare_execution_write_body(mapped(Create), cat, b"{}", 100, {
      ..write_limits(),
      max_input_bytes: 1,
    })
    is Err(Body(BudgetExceeded)),
  )
}

///|
test "mapping retains physical catalog while logical target aliases remain Common-owned" {
  let mapping = prepare_execution_mapping(
    mapping_catalog(),
    "hubspot",
    mapping_manifest(),
    "company_alias",
    Update,
    ["amount"],
    [],
    mapping_limits(),
  ).unwrap()
  assert_eq(mapping.catalog.object_type, "companies")
  assert_true(
    execution_mapping_body(mapping).contains(
      "connector://hubspot/company_alias",
    ),
  )
  // A candidate does not establish membership in a connector declaration.
  // The actual Common consuming case admits the alias and refuses a changed
  // physical Catalog or another connection under the original Mapping.
  assert_true(
    prepare_execution_mapping(
      mapping_catalog(),
      "crm/hubspot",
      mapping_manifest(),
      "companies",
      Update,
      ["amount"],
      [],
      mapping_limits(),
    )
    is Ok(_),
  )
}
