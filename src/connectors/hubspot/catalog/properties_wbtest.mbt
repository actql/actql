///|
fn limits() -> PropertyLimits {
  {
    max_bytes: 20000,
    max_nodes: 2000,
    max_depth: 20,
    max_properties: 100,
    max_name_units: 1000,
  }
}

///|
fn catalog(
  body : String,
  object_type? : String = "companies",
) -> PropertyCatalog {
  project_properties(@utf8.encode(body), object_type, limits()).unwrap()
}

///|
fn same_contract(
  left : @contract.Contract,
  right : @contract.Contract,
) -> Bool raise {
  @contract.type_equal(left, right, 1000)
}

///|
test "account property metadata maps through the actual Common carrier contracts" {
  let properties = catalog(
    (
      #|{"results":[{"name":"amount","type":"number","fieldType":"number"},{"name":"live","type":"bool","fieldType":"booleancheckbox"},{"name":"day","type":"date","fieldType":"date"},{"name":"instant","type":"datetime","fieldType":"date"},{"name":"phone","type":"phone_number","fieldType":"phonenumber"}]}
    ),
  )
  assert_true(
    same_contract(
      property_contract(properties, "amount").unwrap(),
      @contract.decimal_contract(38, 10, nullable=true).unwrap(),
    ),
  )
  for
    (name, kind) in [
      ("live", @contract.BooleanType),
      ("day", @contract.DateType),
      ("instant", @contract.TimestampType),
      ("phone", @contract.StringType),
    ] {
    assert_true(
      same_contract(
        property_contract(properties, name).unwrap(),
        @contract.primitive(kind, nullable=true),
      ),
    )
  }
}

///|
test "checkbox options retain internal values and Common nonnull array elements" {
  let properties = catalog(
    (
      #|{"results":[{"name":"tags","type":"enumeration","fieldType":"checkbox","options":[{"value":"internal_a","label":"Public label"},{"value":"internal_b","label":"Another label"}]},{"name":"stage","type":"enumeration","fieldType":"select","options":[{"value":"qualified","label":"Qualified lead"}]}]}
    ),
  )
  assert_eq(property_named(properties, "tags").unwrap().options, [
    "internal_a", "internal_b",
  ])
  let expected = @contract.array_contract(
    @contract.primitive(@contract.StringType, nullable=false),
    nullable=true,
  ).unwrap()
  assert_true(
    same_contract(property_contract(properties, "tags").unwrap(), expected),
  )
  assert_true(
    same_contract(
      property_contract(properties, "stage").unwrap(),
      @contract.primitive(@contract.StringType, nullable=true),
    ),
  )
}

///|
test "mutable property and option projections cannot alter the original catalog" {
  let properties = catalog(
    (
      #|{"results":[{"name":"stage","type":"enumeration","fieldType":"select","options":[{"value":"original"}]}]}
    ),
  )
  let names = property_names(properties)
  names[0] = "foreign"
  names.push("injected")
  let original = property_named(properties, "stage").unwrap()
  let options = property_option_values(original)
  options[0] = "replaced"
  options.push("injected")
  assert_eq(property_names(properties), ["stage"])
  assert_eq(property_option_values(original), ["original"])
  assert_true(property_named(properties, "foreign") is None)
}

///|
test "new account properties and custom object identity need no static field list" {
  let body =
    #|{"results":[{"name":"new_custom_field","type":"string","fieldType":"text","calculated":false,"hasUniqueValue":true,"modificationMetadata":{"readOnlyValue":false,"readOnlyDefinition":true}}]}
  let properties = catalog(body, object_type="2-12345")
  assert_eq(properties.object_type, "2-12345")
  assert_eq(properties.response_sha256, @sha.hex(@utf8.encode(body)))
  assert_true(property_contract(properties, "new_custom_field") is Ok(_))
  assert_eq(require_property_write(properties, "new_custom_field"), Ok(()))
  assert_eq(require_unique_property(properties, "new_custom_field"), Ok(()))
  assert_true(
    property_contract(properties, "unobserved")
    is Err(PropertyUnconfirmed("unobserved")),
  )
}

///|
test "calculated read-only archived and unknown write metadata never grant eligibility" {
  let properties = catalog(
    (
      #|{"results":[{"name":"score","type":"number","fieldType":"calculation_equation","calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"read_only","type":"string","fieldType":"text","calculated":false,"modificationMetadata":{"readOnlyValue":true}},{"name":"archived","type":"string","fieldType":"text","archived":true,"calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"unknown","type":"string","fieldType":"text"},{"name":"ordinary","type":"string","fieldType":"text","calculated":false,"modificationMetadata":{"readOnlyValue":false}}]}
    ),
  )
  for name in ["score", "read_only", "archived"] {
    assert_eq(
      require_property_write(properties, name),
      Err(ReadOnlyProperty(name)),
    )
  }
  assert_eq(
    require_property_write(properties, "unknown"),
    Err(WriteUnconfirmed("unknown")),
  )
  assert_eq(require_property_write(properties, "ordinary"), Ok(()))
}

///|
test "unique keys are object-scoped and observed custom uniqueness is required" {
  let body =
    #|{"results":[{"name":"email","type":"string","fieldType":"text"},{"name":"domain","type":"string","fieldType":"text"},{"name":"custom_key","type":"string","fieldType":"text","hasUniqueValue":true},{"name":"not_unique","type":"string","fieldType":"text","hasUniqueValue":false}]}
  let contacts = catalog(body, object_type="contacts")
  assert_eq(require_unique_property(contacts, "email"), Ok(()))
  assert_eq(
    require_unique_property(contacts, "domain"),
    Err(UniqueKeyUnconfirmed("domain")),
  )
  let companies = catalog(body)
  assert_eq(
    require_unique_property(companies, "domain"),
    Err(UniqueKeyUnconfirmed("domain")),
  )
  assert_eq(
    require_unique_property(companies, "email"),
    Err(UniqueKeyUnconfirmed("email")),
  )
  assert_eq(require_unique_property(companies, "custom_key"), Ok(()))
  assert_eq(
    require_unique_property(companies, "not_unique"),
    Err(UniqueKeyUnconfirmed("not_unique")),
  )
  assert_eq(
    require_unique_property(companies, "missing"),
    Err(PropertyUnconfirmed("missing")),
  )
}

///|
test "unknown native types stay unconfirmed without hiding supported siblings" {
  let properties = catalog(
    (
      #|{"results":[{"name":"future","type":"future_type","fieldType":"text"},{"name":"strange_enum","type":"enumeration","fieldType":"future_checkbox","options":[]},{"name":"known","type":"string","fieldType":"text"}]}
    ),
  )
  assert_true(
    property_contract(properties, "future")
    is Err(UnsupportedProperty("future")),
  )
  assert_true(
    property_contract(properties, "strange_enum")
    is Err(UnsupportedProperty("strange_enum")),
  )
  assert_true(property_contract(properties, "known") is Ok(_))
}

///|
test "duplicate fields option values and malformed flags refuse the whole observation" {
  let duplicate = @utf8.encode(
    (
      #|{"results":[{"name":"p","type":"string","fieldType":"text"},{"name":"p","type":"string","fieldType":"text"}]}
    ),
  )
  assert_true(
    project_properties(duplicate, "contacts", limits())
    is Err(DuplicateProperty("p")),
  )
  for
    body in [
      (
        #|{"results":[{"name":"p","type":"enumeration","fieldType":"select","options":[{"value":"x"},{"value":"x"}]}]}
      ),
      (
        #|{"results":[{"name":"p","type":"bool","fieldType":"booleancheckbox","calculated":"false"}]}
      ),
      (
        #|{"results":[{"name":"p","type":"string","fieldType":"text","modificationMetadata":null}]}
      ),
      (
        #|{"results":[{"name":"p","type":"string","fieldType":"text","hasUniqueValue":null}]}
      ),
    ] {
    assert_true(
      project_properties(@utf8.encode(body), "contacts", limits())
      is Err(InvalidProperty("p")),
    )
  }
}

///|
test "bounded whole response parsing refuses truncation duplicate JSON keys and exhausted budgets" {
  let body = @utf8.encode(
    (
      #|{"results":[{"name":"field_one","type":"string","fieldType":"text"},{"name":"field_two","type":"string","fieldType":"text"}]}
    ),
  )
  assert_true(
    project_properties(body, "contacts", {
      ..limits(),
      max_bytes: body.length() - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_properties(body, "contacts", { ..limits(), max_properties: 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_properties(body, "contacts", { ..limits(), max_name_units: 10, })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_properties(body, "contacts", { ..limits(), max_nodes: 2, })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_properties(body, "contacts", { ..limits(), max_depth: 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_properties(body, "contacts", { ..limits(), max_bytes: 0, })
    is Err(InvalidLimits),
  )
  assert_true(
    project_properties(
      @utf8.encode("{\"results\":[],\"results\":[]}"),
      "contacts",
      limits(),
    )
    is Err(InvalidResponse),
  )
  assert_true(
    project_properties(@utf8.encode("{\"results\":["), "contacts", limits())
    is Err(InvalidResponse),
  )
  assert_true(
    project_properties(
      @utf8.encode("{\"status\":\"error\"}"),
      "contacts",
      limits(),
    )
    is Err(InvalidResponse),
  )
}

///|
test "company domain with explicit false uniqueness is not an API candidate key" {
  let properties = catalog(
    (
      #|{"results":[{"name":"domain","type":"string","fieldType":"text","hasUniqueValue":false}]}
    ),
  )
  assert_eq(
    require_unique_property(properties, "domain"),
    Err(UniqueKeyUnconfirmed("domain")),
  )
}

///|
test "company domain with missing uniqueness is not an API candidate key" {
  let properties = catalog(
    (
      #|{"results":[{"name":"domain","type":"string","fieldType":"text"}]}
    ),
  )
  assert_eq(
    require_unique_property(properties, "domain"),
    Err(UniqueKeyUnconfirmed("domain")),
  )
}

///|
test "record ids and positively enforced custom keys remain available for API targets" {
  let properties = catalog(
    (
      #|{"results":[{"name":"hs_object_id","type":"number","fieldType":"number","hasUniqueValue":false},{"name":"external_key","type":"string","fieldType":"text","hasUniqueValue":true,"calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"label","type":"string","fieldType":"text","hasUniqueValue":false}]}
    ),
  )
  assert_eq(require_unique_property(properties, "hs_object_id"), Ok(()))
  assert_eq(require_unique_property(properties, "external_key"), Ok(()))
  assert_eq(require_property_write(properties, "external_key"), Ok(()))
  assert_eq(
    require_unique_property(properties, "label"),
    Err(UniqueKeyUnconfirmed("label")),
  )
}

///|
test "enumeration rollup keeps its result carrier through schema and row projection" {
  let original = catalog(
    (
      #|{"results":[{"name":"rollup","type":"enumeration","fieldType":"calculation_rollup","calculated":false,"options":[],"modificationMetadata":{"readOnlyValue":true}},{"name":"name","type":"string","fieldType":"text"}]}
    ),
  )
  assert_true(
    same_contract(
      property_contract(original, "rollup").unwrap(),
      @contract.primitive(@contract.StringType, nullable=true),
    ),
  )
  assert_eq(
    object_schema_wire(original, ["rollup", "name"], 3, 100, 4096, 100, 10),
    Ok(
      "{\"id\":{\"nullable\":false,\"type\":\"string\"},\"name\":{\"nullable\":true,\"type\":\"string\"},\"rollup\":{\"nullable\":true,\"type\":\"string\"}}",
    ),
  )
  let observed = project_object_page(
    @utf8.encode(
      (
        #|{"results":[{"id":"9007199254740993","archived":false,"properties":{"rollup":"internal_7","name":"ordinary"}},{"id":"2","archived":false,"properties":{"rollup":"","name":"other"}}]}
      ),
    ),
    original,
    ["rollup", "name"],
    page_limits(),
  ).unwrap()
  let rows = object_page_rows(observed)
  assert_eq(rows[0].id, "9007199254740993")
  assert_true(
    object_row_values(rows[0])[0].value is @admitted.Text("internal_7"),
  )
  assert_true(object_row_values(rows[1])[0].value is @admitted.Null)
}

///|
test "enumeration rollup cannot acquire write eligibility from false provider flags" {
  let original = catalog(
    (
      #|{"results":[{"name":"rollup","type":"enumeration","fieldType":"calculation_rollup","calculated":false,"options":[],"modificationMetadata":{"readOnlyValue":false}},{"name":"ordinary","type":"enumeration","fieldType":"select","calculated":false,"options":[{"value":"internal"}],"modificationMetadata":{"readOnlyValue":false}}]}
    ),
  )
  assert_eq(
    require_property_write(original, "rollup"),
    Err(ReadOnlyProperty("rollup")),
  )
  assert_eq(require_property_write(original, "ordinary"), Ok(()))
}
