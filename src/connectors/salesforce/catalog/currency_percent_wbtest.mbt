///|
/// Independent provider Describe bytes; no public grant or real org.
fn money_rate_describe(
  native_type : String,
  precision? : Int? = Some(16),
  scale? : Int? = Some(2),
) -> String {
  let digits = match precision {
    Some(value) => ",\"precision\":" + value.to_string()
    None => ""
  }
  let fraction = match scale {
    Some(value) => ",\"scale\":" + value.to_string()
    None => ""
  }
  "{\"name\":\"Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true,\"fields\":[" +
  "{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false}," +
  "{\"name\":\"Value__c\",\"type\":\"" +
  native_type +
  "\"" +
  digits +
  fraction +
  ",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}]}"
}

///|
fn money_rate_observation(
  native_type : String,
  precision? : Int? = Some(16),
  scale? : Int? = Some(2),
) -> (CatalogObservation, CatalogObservationBinding) {
  declared_observation(money_rate_describe(native_type, precision~, scale~))
}

///|
fn money_rate_read(native_type : String) -> ReadProjection {
  let (observation, binding) = money_rate_observation(native_type)
  prepare_read_projection(observation, binding, "Record__c", ["Value__c"], 256).unwrap()
}

///|
fn money_rate_write(native_type : String) -> WriteProjection {
  let (observation, binding) = money_rate_observation(native_type)
  prepare_write_projection(
    observation,
    binding,
    "Record__c",
    WriteUpdateById,
    ["Value__c"],
    1,
  ).unwrap()
}

///|
fn money_rate_page(
  projection : ReadProjection,
  number_text : String,
) -> Result[QueryPage, QueryPageIssue] {
  project_query_page(
    @utf8.encode(
      "{\"totalSize\":1,\"done\":true,\"records\":[{\"Value__c\":" +
      number_text +
      "}]}",
    ),
    projection,
    "v62.0",
    query_test_limits(),
  )
}

///|
fn money_rate_body(
  projection : WriteProjection,
  value : String,
) -> Result[WriteBody, WriteBodyIssue] {
  prepare_write_body(projection, @utf8.encode("{\"Value__c\":" + value + "}"), {
    max_bytes: 1000,
    max_nodes: 20,
    max_depth: 2,
  })
}

///|
test "Currency and Percent preserve the actual described precision scale and native type" {
  for native_type in ["currency", "percent"] {
    let (observation, binding) = money_rate_observation(native_type)
    let field = catalog_observation_resource(observation, binding, "Record__c").unwrap().fields[1]
    assert_eq(field.native_type, native_type)
    assert_eq(field.precision, Some(16))
    assert_eq(field.scale, Some(2))
    assert_true(read_field_contract(field) is Some(_))
  }
}

///|
test "Currency and Percent declarations issue the original exact decimal schema and writable fields" {
  for native_type in ["currency", "percent"] {
    let declaration = declared_for(money_rate_describe(native_type))
    assert_eq(declaration.views[0].fields, ["Id", "Value__c"])
    assert_true(
      declaration.catalog.contains(
        "\"Value__c\":{\"nullable\":true,\"precision\":16,\"scale\":2,\"type\":\"decimal\"}",
      ),
    )
    assert_eq(declaration.writables[0].create_fields, Some(["Value__c"]))
    assert_eq(declaration.writables[0].update_fields, Some(["Value__c"]))
    assert_eq(declaration.exclusions.length(), 0)
    let (observation, binding) = money_rate_observation(native_type)
    let plan = prepare_read_projection(
      observation,
      binding,
      "Record__c",
      ["Value__c"],
      256,
    ).unwrap()
    assert_true(recheck_read_projection(plan, observation) is Ok(_))
  }
}

///|
test "Currency and Percent read original number digits without conversion rounding or percent scaling" {
  for native_type in ["currency", "percent"] {
    let plan = money_rate_read(native_type)
    for
      (input, expected) in [
        ("12345678901234.56", "1234567890123456e-2"),
        ("1.234567890123456E13", "1234567890123456e-2"),
        ("12.5", "1250e-2"),
        ("-0.1", "-10e-2"),
        ("-0.0", "0e-2"),
      ] {
      let page = money_rate_page(plan, input)
      assert_true(page is Ok(_), msg=native_type + " " + input)
      assert_eq(
        decimal_cell(page.unwrap(), 0),
        Some(expected),
      )
    }
    assert_true(
      query_page_cell(money_rate_page(plan, "null").unwrap(), 0, 0).unwrap().value
      is @admitted.Null,
    )
    for
      (input, kind) in [
        ("100000000000000", "range"),
        ("0.001", "scale"),
        ("\"12.50\"", "type"),
      ] {
      let issue = query_page_value_violation(
        money_rate_page(plan, input).unwrap_err(),
        plan,
      ).unwrap()
      assert_eq((issue.field, issue.kind), ("Value__c", kind))
    }
  }
}

///|
test "Currency and Percent write only the same approved canonical decimal number text" {
  for native_type in ["currency", "percent"] {
    let projection = money_rate_write(native_type)
    let body = money_rate_body(projection, "\"12345678901234.56\"").unwrap()
    assert_eq(write_body_json(body), "{\"Value__c\":12345678901234.56}")
    assert_eq(
      write_body_value_json(body),
      "{\"Value__c\":\"12345678901234.56\"}",
    )
    assert_eq(
      write_body_json(money_rate_body(projection, "\"12.50\"").unwrap()),
      "{\"Value__c\":12.50}",
    )
    assert_eq(
      money_rate_body(projection, "\"0.001\"").unwrap_err(),
      ValueBeyondScale("Value__c"),
    )
    assert_eq(
      money_rate_body(projection, "\"100000000000000.00\"").unwrap_err(),
      ValueOutOfRange("Value__c"),
    )
    assert_eq(
      money_rate_body(projection, "12.50").unwrap_err(),
      InvalidValue("Value__c"),
    )
    assert_eq(
      money_rate_body(projection, "\"12.5\"").unwrap_err(),
      InvalidValue("Value__c"),
    )
  }
}

///|
test "Currency and Percent target observation Preview and recovery retain original decimal units" {
  for native_type in ["currency", "percent"] {
    let projection = money_rate_write(native_type)
    let body = money_rate_body(projection, "\"12.50\"").unwrap()
    let request = prepare_single_write_request(
      body,
      "v62.0",
      RecordId("a01000000000001"),
      write_request_test_limits(),
    ).unwrap()
    let observed = prepare_target_observation(
      request,
      200,
      @utf8.encode("{\"Id\":\"a01000000000001AAA\",\"Value__c\":-0.1}"),
      target_observation_test_limits(),
    ).unwrap()
    assert_eq(
      target_observation_before_value_wire(observed),
      "{\"Value__c\":\"-0.10\"}",
    )
    let row = prepare_observed_target_preview_row(request, observed, 1024).unwrap()
    assert_eq(target_preview_row_after_wire(row), "{\"Value__c\":\"12.50\"}")
    let recovered = recover_single_write_request(
      projection,
      single_write_request_value(request),
      "\"a01000000000001\"",
      "v62.0",
      { max_bytes: 1000, max_nodes: 20, max_depth: 2, },
      write_request_test_limits(),
    ).unwrap()
    assert_eq(
      single_write_request_body(recovered),
      single_write_request_body(request),
    )
  }
}

///|
test "missing or unsupported Currency and Percent digit metadata never receives a default contract" {
  for native_type in ["currency", "percent"] {
    for
      (precision, scale) in [
        (None, Some(2)),
        (Some(16), None),
        (Some(39), Some(2)),
        (Some(2), Some(3)),
      ] {
      let (observation, binding) = money_rate_observation(
        native_type,
        precision~,
        scale~,
      )
      assert_true(
        prepare_read_projection(
          observation,
          binding,
          "Record__c",
          ["Value__c"],
          256,
        )
        is Err(UnsupportedReadType("Value__c")),
      )
      assert_true(
        prepare_write_projection(
          observation,
          binding,
          "Record__c",
          WriteUpdateById,
          ["Value__c"],
          1,
        )
        is Err(UnsupportedWriteType("Value__c")),
      )
      let declaration = declared_for(
        money_rate_describe(native_type, precision~, scale~),
      )
      assert_true(
        declaration.exclusions.contains({
          resource: "Record__c",
          field: "Value__c",
          reason: UnsupportedPrecision(precision, scale),
        }),
      )
      let wire = static_declaration_json(declaration, declaration_limits()).unwrap()
      assert_true(
        wire.contains(
          "\"kind\":\"unsupported_precision\",\"native_type\":\"" +
          native_type +
          "\"",
        ),
      )
    }
  }
}

///|
test "malformed Currency and Percent precision metadata is an original Describe refusal" {
  for native_type in ["currency", "percent"] {
    let body = money_rate_describe(native_type).replace_all(
      old="\"precision\":16",
      new="\"precision\":\"16\"",
    )
    assert_true(
      project_describe(@utf8.encode(body), "Record__c", {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 10,
        max_fields: 20,
        max_name_units: 1000,
      })
      is Err(InvalidField("Value__c")),
    )
  }
}

///|
test "equal decimal shapes do not erase a change between original currency and percent metadata" {
  let (currency, binding) = money_rate_observation("currency")
  let (percent, _) = money_rate_observation("percent")
  let read = prepare_read_projection(
    currency,
    binding,
    "Record__c",
    ["Value__c"],
    256,
  ).unwrap()
  let write = prepare_write_projection(
    currency,
    binding,
    "Record__c",
    WriteUpdateById,
    ["Value__c"],
    1,
  ).unwrap()
  assert_true(
    recheck_read_projection(read, percent) is Err(SchemaChanged("Value__c")),
  )
  assert_true(
    recheck_write_projection(write, percent) is Err(SchemaChanged("Value__c")),
  )
}
