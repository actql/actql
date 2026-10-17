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
