///|
/// Original standard/custom Describe associations, including configured codes.
fn address_describe(custom? : Bool = false, codes? : Bool = false) -> String {
  let parent = if custom { "Address__c" } else { "BillingAddress" }
  let fields = [
    "{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false}",
    "{\"name\":\"" +
    parent +
    "\",\"type\":\"address\",\"nillable\":true,\"createable\":false,\"updateable\":false}",
  ]
  let components = [
    ("City", "string"),
    ("GeocodeAccuracy", "picklist"),
    ("Latitude", "double"),
    ("Longitude", "double"),
    ("PostalCode", "string"),
    ("Street", "textarea"),
  ]
  if !custom {
    components.push(("Country", "string"))
    components.push(("State", "string"))
  }
  if custom || codes {
    components.push(("CountryCode", "picklist"))
    components.push(("StateCode", "picklist"))
  }
  for (role, kind) in components {
    let name = if custom {
      "Address__" + role + "__s"
    } else {
      "Billing" + role
    }
    let digits = if kind == "double" {
      ",\"precision\":18,\"scale\":15"
    } else {
      ""
    }
    fields.push(
      "{\"name\":\"" +
      name +
      "\",\"type\":\"" +
      kind +
      "\",\"compoundFieldName\":\"" +
      parent +
      "\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true" +
      digits +
      "}",
    )
  }
  "{\"name\":\"Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true,\"fields\":[" +
  fields.join(",") +
  "]}"
}

///|
test "compound Address declaration uses original standard and custom component contracts" {
  for custom in [false, true] {
    let parent = if custom { "Address__c" } else { "BillingAddress" }
    let declaration = declared_for(address_describe(custom~))
    assert_true(declaration.views[0].fields.contains(parent))
    assert_true(
      declaration.catalog.contains(
        "\"" + parent + "\":{\"additional_properties\":false,\"fields\":{",
      ),
    )
    assert_true(
      declaration.catalog.contains(
        "\"latitude\":{\"nullable\":true,\"precision\":18,\"scale\":15,\"type\":\"decimal\"}",
      ),
    )
  }
}

///|
test "compound Address preserves original Unicode text decimal lexemes and explicit nulls" {
  let (observation, binding) = declared_observation(address_describe())
  let plan = prepare_read_projection(
    observation,
    binding,
    "Record__c",
    ["BillingAddress"],
    256,
  ).unwrap()
  let page = project_query_page(
    @utf8.encode(
      (
        #|{"totalSize":1,"done":true,"records":[{"BillingAddress":{"city":"東京","country":"日本","geocodeAccuracy":"Address","latitude":35.123456789012345,"longitude":139.123456789012345,"postalCode":"001-0001","state":null,"street":"a\nb"}}]}
      ),
    ),
    plan,
    "v62.0",
    query_test_limits(),
  ).unwrap()
  let writer = @encode.writer(4096, 100, 10) catch { _ => abort("test writer") }
  @admitted.emit_checked_wire_value(
    query_page_cell(page, 0, 0).unwrap(),
    writer,
  ) catch {
    _ => abort("test value")
  }
  let wire = @encode.finish(writer) catch { _ => abort("test finish") }
  assert_eq(
    wire, "{\"city\":\"東京\",\"country\":\"日本\",\"geocodeAccuracy\":\"Address\",\"latitude\":\"35.123456789012345\",\"longitude\":\"139.123456789012345\",\"postalCode\":\"001-0001\",\"state\":null,\"street\":\"a\\nb\"}",
  )
}

///|
fn address_test_plan(
  custom? : Bool = false,
  codes? : Bool = false,
) -> ReadProjection {
  let (observation, binding) = declared_observation(
    address_describe(custom~, codes~),
  )
  prepare_read_projection(
    observation,
    binding,
    "Record__c",
    [if custom { "Address__c" } else { "BillingAddress" }],
    256,
  ).unwrap()
}

///|
fn address_test_cell(
  plan : ReadProjection,
  cell : String,
  custom? : Bool = false,
  limits? : QueryPageLimits = query_test_limits(),
) -> Result[QueryPage, QueryPageIssue] {
  let parent = if custom { "Address__c" } else { "BillingAddress" }
  project_query_page(
    @utf8.encode(
      "{\"totalSize\":1,\"done\":true,\"records\":[{\"" +
      parent +
      "\":" +
      cell +
      "}]}",
    ),
    plan,
    "v62.0",
    limits,
  )
}

///|
fn address_standard_cell() -> String {
  (
    #|{"city":"東京","country":"日本","geocodeAccuracy":"Address","latitude":35.1,"longitude":139.2,"postalCode":"001-0001","state":null,"street":"a\nb"}
  )
}

///|
test "compound Address keeps standard integration values and codes distinct" {
  let plan = address_test_plan(codes=true)
  assert_eq(read_projection_soql(plan), "SELECT BillingAddress FROM Record__c")
  let page = address_test_cell(
    plan,
    (
      #|{"city":"東京","country":"Japan integration","countryCode":"JP","geocodeAccuracy":null,"latitude":35,"longitude":139,"postalCode":"000","state":"Tokyo integration","stateCode":"13","street":""}
    ),
  ).unwrap()
  let value = query_page_cell(page, 0, 0).unwrap()
  let writer = @encode.writer(4096, 100, 10) catch { _ => abort("test writer") }
  @admitted.emit_checked_wire_value(value, writer) catch {
    _ => abort("test value")
  }
  assert_eq(
    @encode.finish(writer) catch {
      _ => abort("test finish")
    },
    "{\"city\":\"東京\",\"country\":\"Japan integration\",\"countryCode\":\"JP\",\"geocodeAccuracy\":null,\"latitude\":\"35.000000000000000\",\"longitude\":\"139.000000000000000\",\"postalCode\":\"000\",\"state\":\"Tokyo integration\",\"stateCode\":\"13\",\"street\":\"\"}",
  )
}

///|
test "compound custom Address uses original code components without inventing labels" {
  let plan = address_test_plan(custom=true)
  assert_eq(read_projection_soql(plan), "SELECT Address__c FROM Record__c")
  let page = address_test_cell(
    plan,
    (
      #|{"city":"東京","countryCode":"JP","geocodeAccuracy":null,"latitude":null,"longitude":null,"postalCode":"001","stateCode":"13","street":""}
    ),
    custom=true,
  ).unwrap()
  assert_eq(query_page_row_count(page), 1)
  assert_true(
    address_test_cell(
      plan,
      (
        #|{"city":"東京","country":"invented","countryCode":"JP","geocodeAccuracy":null,"latitude":null,"longitude":null,"postalCode":"001","stateCode":"13","street":""}
      ),
      custom=true,
    )
    is Err(InvalidResponse),
  )
}

///|
test "compound Address requires positive complete original parent associations" {
  for
    changed in [
      address_describe().replace_all(
        old=",\"compoundFieldName\":\"BillingAddress\"",
        new="",
      ),
      address_describe().replace_all(
        old="\"BillingLatitude\"",
        new="\"BillingAltitude\"",
      ),
      address_describe().replace_all(
        old="\"compoundFieldName\":\"BillingAddress\"",
        new="\"compoundFieldName\":\"OtherAddress\"",
      ),
      address_describe().replace_all(old=",\"scale\":15", new=""),
      address_describe(custom=true).replace_all(
        old="\"Address__StateCode__s\"",
        new="\"Address__Country__s\"",
      ),
    ] {
    let parent = if changed.contains("Address__c") {
      "Address__c"
    } else {
      "BillingAddress"
    }
    let (observation, binding) = declared_observation(changed)
    assert_true(
      prepare_read_projection(observation, binding, "Record__c", [parent], 256)
      is Err(UnsupportedReadType(_)),
    )
    assert_true(!declared_for(changed).views[0].fields.contains(parent))
  }
}

///|
test "compound Address rejects ambiguous unknown and non-text component roles" {
  for
    (old, new) in [
      ("\"BillingCountry\"", "\"OtherCity\""),
      ("\"BillingCity\"", "\"BillingProvince\""),
      ("\"type\":\"textarea\"", "\"type\":\"boolean\""),
    ] {
    let (observation, binding) = declared_observation(
      address_describe().replace_all(old~, new~),
    )
    assert_true(
      prepare_read_projection(
        observation,
        binding,
        "Record__c",
        ["BillingAddress"],
        256,
      )
      is Err(UnsupportedReadType("BillingAddress")),
    )
  }
}

///|
test "compound Address rechecks original component meaning and configured shape" {
  let plan = address_test_plan()
  for
    changed in [
      address_describe().replace_all(old="\"scale\":15", new="\"scale\":14"),
      address_describe().replace_all(
        old="\"compoundFieldName\":\"BillingAddress\"",
        new="\"compoundFieldName\":\"OtherAddress\"",
      ),
      address_describe().replace_all(
        old="\"nillable\":true",
        new="\"nillable\":false",
      ),
      address_describe(codes=true),
    ] {
    let (current, _) = declared_observation(changed)
    assert_true(
      recheck_read_projection(plan, current)
      is Err(SchemaChanged("BillingAddress")),
    )
  }
}

///|
test "compound Address binds every original caller Contract and refuses a changed child" {
  let plan = address_test_plan(codes=true)
  let caller = address_contract(plan.fields[0], plan.field_components[0]).unwrap()
  assert_true(bind_read_projection_contracts(plan, [caller]) is Some(_))
  let changed = plan.field_components[0].map(part => {
    if part.0 == "latitude" {
      (part.0, { ..part.1, scale: Some(14), })
    } else {
      part
    }
  })
  assert_true(
    bind_read_projection_contracts(plan, [
      address_contract(plan.fields[0], changed).unwrap(),
    ])
    is None,
  )
  let wire = read_field_contract_json(
      plan.fields[0],
      components=plan.field_components[0],
    )
    .unwrap()
    .stringify()
  let parsed = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 4096,
    max_nodes: 100,
    max_depth: 8,
  }).unwrap()
  let cursor = @decode.admit(parsed, {
    max_nodes: 100,
    max_depth: 8,
    max_string_bytes: 4096,
    max_total_string_bytes: 4096,
  }).unwrap()
  assert_true(
    @contract.read_checked(cursor, {
      max_nodes: 100,
      max_depth: 8,
      max_text_bytes: 4096,
    })
    is Ok(_),
  )
}

///|
test "compound Address refuses missing extra coerced and excess-scale provider values" {
  let plan = address_test_plan()
  for
    changed in [
      address_standard_cell().replace_all(old="\"city\":\"東京\",", new=""),
      address_standard_cell().replace_all(
        old="\"city\":\"東京\"",
        new="\"city\":17",
      ),
      address_standard_cell().replace_all(
        old="\"latitude\":35.1",
        new="\"latitude\":\"35.1\"",
      ),
      address_standard_cell().replace_all(
        old="\"latitude\":35.1",
        new="\"latitude\":35.0000000000000001",
      ),
      address_standard_cell().replace_all(
        old="\"city\":",
        new="\"unknown\":null,\"city\":",
      ),
    ] {
    assert_true(address_test_cell(plan, changed) is Err(_))
  }
  assert_true(address_test_cell(plan, "null") is Ok(_))
  assert_true(
    address_test_cell(
      plan,
      address_standard_cell().replace_all(old="35.1", new="null"),
    )
    is Ok(_),
  )
}

///|
test "compound Address keeps original byte node and depth bounds and typed value refusal" {
  let plan = address_test_plan()
  let limits = query_test_limits()
  for
    limited in [
      { ..limits, max_bytes: 32, },
      { ..limits, max_nodes: 8, },
      { ..limits, max_depth: 2, },
    ] {
    assert_true(
      address_test_cell(plan, address_standard_cell(), limits=limited)
      is Err(BudgetExceeded),
    )
  }
  let failure = address_test_cell(
    plan,
    address_standard_cell().replace_all(old="35.1", new="35.0000000000000001"),
  )
  guard failure is Err(issue) else { abort("expected original scale refusal") }
  let violation = query_page_value_violation(issue, plan).unwrap()
  assert_eq(violation.resource, "Record__c")
  assert_eq(violation.field, "BillingAddress")
  assert_eq(violation.expected_type, "object")
  assert_eq(violation.kind, "scale")
}

///|
test "compound Address writes retain component mapping and refuse the parent" {
  let (observation, binding) = declared_observation(address_describe())
  let write = prepare_write_projection(
    observation,
    binding,
    "Record__c",
    WriteUpdateById,
    ["BillingCity", "BillingStreet"],
    2,
  ).unwrap()
  let body = prepare_write_body(
    write,
    @utf8.encode("{\"BillingCity\":\"東京\",\"BillingStreet\":\"a\\nb\"}"),
    { max_bytes: 4096, max_nodes: 20, max_depth: 3, },
  ).unwrap()
  assert_eq(
    write_body_json(body),
    "{\"BillingCity\":\"東京\",\"BillingStreet\":\"a\\nb\"}",
  )
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "Record__c",
      WriteUpdateById,
      ["BillingAddress"],
      1,
    )
    is Err(_),
  )
  let (custom, custom_binding) = declared_observation(
    address_describe(custom=true),
  )
  let code_write = prepare_write_projection(
    custom,
    custom_binding,
    "Record__c",
    WriteUpdateById,
    ["Address__CountryCode__s", "Address__StateCode__s"],
    2,
  ).unwrap()
  assert_eq(
    write_body_json(
      prepare_write_body(
        code_write,
        @utf8.encode(
          "{\"Address__CountryCode__s\":\"JP\",\"Address__StateCode__s\":\"13\"}",
        ),
        { max_bytes: 4096, max_nodes: 20, max_depth: 3, },
      ).unwrap(),
    ),
    "{\"Address__CountryCode__s\":\"JP\",\"Address__StateCode__s\":\"13\"}",
  )
}
