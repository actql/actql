///|
fn declared_decimal_read(precision : Int, scale : Int) -> ReadProjection {
  let (observation, binding) = number_observation(
    wide_precision=precision,
    wide_scale=scale,
  )
  prepare_read_projection(observation, binding, "Order__c", ["Wide__c"], 256).unwrap()
}

///|
fn declared_decimal_page(
  projection : ReadProjection,
  number_text : String,
) -> Result[QueryPage, QueryPageIssue] {
  project_query_page(
    @utf8.encode(
      "{\"totalSize\":1,\"done\":true,\"records\":[{\"Wide__c\":" +
      number_text +
      "}]}",
    ),
    projection,
    "v62.0",
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_rows: 4,
      max_locator_units: 128,
    },
  )
}

///|
fn declared_decimal_write(precision : Int, scale : Int) -> WriteProjection {
  let (observation, binding) = number_observation(
    wide_precision=precision,
    wide_scale=scale,
  )
  prepare_write_projection(
    observation,
    binding,
    "Order__c",
    WriteUpdateById,
    ["Wide__c"],
    1,
  ).unwrap()
}

///|
fn declared_decimal_body(
  projection : WriteProjection,
  value : String,
) -> Result[WriteBody, WriteBodyIssue] {
  prepare_write_body(projection, @utf8.encode("{\"Wide__c\":" + value + "}"), {
    max_bytes: 1000,
    max_nodes: 20,
    max_depth: 2,
  })
}

///|
test "described Number precision uses the existing Decimal Contract range" {
  let (observation, binding) = number_observation()
  let original = catalog_observation_resource(observation, binding, "Order__c").unwrap().fields[3]
  for (precision, scale) in [(1, 0), (16, 2), (18, 0), (38, 2), (38, 38)] {
    let described = {
      ..original,
      precision: Some(precision),
      scale: Some(scale),
    }
    assert_eq(double_decimal(described), Some((precision, scale)))
    assert_true(
      @contract.decimal_contract(precision, scale, nullable=true) is Some(_),
    )
  }
  for (precision, scale) in [(0, 0), (-1, 0), (39, 0), (16, -1), (16, 17)] {
    let described = {
      ..original,
      precision: Some(precision),
      scale: Some(scale),
    }
    assert_eq(double_decimal(described), None)
  }
  assert_eq(double_decimal({ ..original, precision: None, }), None)
  assert_eq(double_decimal({ ..original, scale: None, }), None)
  assert_eq(double_decimal({ ..original, native_type: "currency", }), None)
}

///|
test "declared Number16 read preserves digits exponent null range and scale" {
  let projection = declared_decimal_read(16, 2)
  assert_eq(
    decimal_cell(
      declared_decimal_page(projection, "12345678901234.56").unwrap(),
      0,
    ),
    Some("1234567890123456e-2"),
  )
  assert_eq(
    decimal_cell(
      declared_decimal_page(projection, "1.234567890123456E13").unwrap(),
      0,
    ),
    Some("1234567890123456e-2"),
  )
  assert_eq(
    decimal_cell(
      declared_decimal_page(projection, "-99999999999999.99").unwrap(),
      0,
    ),
    Some("-9999999999999999e-2"),
  )
  assert_true(
    query_page_cell(declared_decimal_page(projection, "null").unwrap(), 0, 0).unwrap().value
    is @admitted.Null,
  )
  for
    (number_text, kind) in [
      ("100000000000000.00", "range"),
      ("1.005", "scale"),
      ("\"12.50\"", "type"),
    ] {
    let violation = query_page_value_violation(
      declared_decimal_page(projection, number_text).unwrap_err(),
      projection,
    ).unwrap()
    assert_eq((violation.field, violation.kind), ("Wide__c", kind))
  }
}

///|
test "declared Number38 read preserves its exact decimal boundary" {
  let projection = declared_decimal_read(38, 2)
  assert_eq(
    decimal_cell(
      declared_decimal_page(
        projection, "999999999999999999999999999999999999.99",
      ).unwrap(),
      0,
    ),
    Some("99999999999999999999999999999999999999e-2"),
  )
  assert_true(
    declared_decimal_page(
      projection, "1000000000000000000000000000000000000.00",
    )
    is Err(_),
  )
  let fraction = declared_decimal_read(38, 38)
  assert_eq(
    decimal_cell(
      declared_decimal_page(
        fraction, "0.12345678901234567890123456789012345678",
      ).unwrap(),
      0,
    ),
    Some("12345678901234567890123456789012345678e-38"),
  )
}

///|
test "declared Number16 request Preview and recovery preserve the same digits" {
  let projection = declared_decimal_write(16, 2)
  let body = declared_decimal_body(projection, "\"12345678901234.56\"").unwrap()
  assert_eq(write_body_json(body), "{\"Wide__c\":12345678901234.56}")
  assert_eq(write_body_value_json(body), "{\"Wide__c\":\"12345678901234.56\"}")
  let request = prepare_single_write_request(
    body,
    "v62.0",
    RecordId("a01000000000001"),
    write_request_test_limits(),
  ).unwrap()
  let observed = prepare_target_observation(
    request,
    200,
    @utf8.encode(
      "{\"Id\":\"a01000000000001AAA\",\"Wide__c\":-99999999999999.99}",
    ),
    target_observation_test_limits(),
  ).unwrap()
  assert_eq(
    target_observation_before_value_wire(observed),
    "{\"Wide__c\":\"-99999999999999.99\"}",
  )
  let row = prepare_observed_target_preview_row(request, observed, 1024).unwrap()
  assert_eq(
    target_preview_row_after_wire(row),
    "{\"Wide__c\":\"12345678901234.56\"}",
  )
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
  assert_eq(
    declared_decimal_body(projection, "\"1.005\"").unwrap_err(),
    ValueBeyondScale("Wide__c"),
  )
  assert_eq(
    declared_decimal_body(projection, "\"100000000000000.00\"").unwrap_err(),
    ValueOutOfRange("Wide__c"),
  )
  assert_eq(
    declared_decimal_body(projection, "12345678901234.56").unwrap_err(),
    InvalidValue("Wide__c"),
  )
}

///|
test "declared Number38 write never passes the approved decimal through binary64" {
  let projection = declared_decimal_write(38, 2)
  let body = declared_decimal_body(
    projection, "\"999999999999999999999999999999999999.99\"",
  ).unwrap()
  assert_eq(
    write_body_json(body),
    "{\"Wide__c\":999999999999999999999999999999999999.99}",
  )
  assert_eq(
    write_body_value_json(body),
    "{\"Wide__c\":\"999999999999999999999999999999999999.99\"}",
  )
  assert_eq(
    declared_decimal_body(projection, "\"0.001\"").unwrap_err(),
    ValueBeyondScale("Wide__c"),
  )
  assert_eq(
    declared_decimal_body(
      projection, "\"1000000000000000000000000000000000000.00\"",
    ).unwrap_err(),
    ValueOutOfRange("Wide__c"),
  )
}

///|
test "metadata outside the Decimal Contract remains unsupported for read and write" {
  let (observation, binding) = number_observation(
    wide_precision=39,
    wide_scale=2,
  )
  assert_true(
    prepare_read_projection(observation, binding, "Order__c", ["Wide__c"], 256)
    is Err(UnsupportedReadType("Wide__c")),
  )
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "Order__c",
      WriteUpdateById,
      ["Wide__c"],
      1,
    )
    is Err(UnsupportedWriteType("Wide__c")),
  )
}
