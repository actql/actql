///|
test "a JSON number is read as decimal(P,S) from its digits alone" {
  // Fixed expectations: exact values at the declared scale.
  let cases = [
    ("12.5", 12, 2, "12.50"),
    ("12.50", 12, 2, "12.50"),
    ("12.500", 12, 2, "12.50"),
    ("-0.1", 12, 2, "-0.10"),
    ("0.1", 15, 15, "0.100000000000000"),
    ("0", 12, 2, "0.00"),
    ("-0.0", 12, 2, "0.00"),
    ("0E+10", 3, 0, "0"),
    ("1.2345678E7", 12, 2, "12345678.00"),
    ("1.2345678e+7", 12, 2, "12345678.00"),
    ("125E-2", 12, 2, "1.25"),
    ("123456789012.345", 15, 3, "123456789012.345"),
    ("999999999999999", 15, 0, "999999999999999"),
    ("-999999999999.99", 14, 2, "-999999999999.99"),
    ("7", 1, 0, "7"),
    ("0.5", 1, 1, "0.5"),
  ]
  for case in cases {
    let (lexeme, precision, scale, expected) = case
    assert_eq(
      json_number_decimal(lexeme, precision, scale) is Ok(text) &&
      text == expected,
      true,
      msg=lexeme,
    )
  }
  // A nonzero digit beyond the scale is never rounded.
  for lexeme in ["12.505", "0.001", "1E-3", "1.2345678901234567E7"] {
    assert_true(json_number_decimal(lexeme, 12, 2) is Err(DecimalScale))
  }
  // More integer digits than P − S.
  for lexeme in ["10000000000", "1E10", "-12345678901"] {
    assert_true(json_number_decimal(lexeme, 12, 2) is Err(DecimalRange))
  }
  assert_true(json_number_decimal("1E999999999", 12, 2) is Err(DecimalRange))
  assert_true(json_number_decimal("1E-999999999", 12, 2) is Err(DecimalScale))
  // Not a JSON number.
  for
    lexeme in [
      "", "-", "+1", "01", ".5", "1.", "1e", "1e+", "0x10", "1 ", "NaN",
    ] {
    assert_true(json_number_decimal(lexeme, 12, 2) is Err(DecimalFormat))
  }
}

///|
test "an approved decimal must be its canonical ActQL spelling" {
  assert_eq(decimal_write_issue("12.50", 12, 2, "F"), None)
  assert_eq(decimal_write_issue("-0.10", 12, 2, "F"), None)
  assert_eq(decimal_write_issue("0.00", 12, 2, "F"), None)
  // Not the fixed-scale spelling: a missing or extra digit, an exponent,
  // negative zero or a leading zero.
  for text in ["12.5", "12.500", "1.25E1", "-0.00", "012.50", "12", ""] {
    assert_eq(decimal_write_issue(text, 12, 2, "F"), Some(InvalidValue("F")))
  }
  assert_eq(
    decimal_write_issue("12345678901.00", 12, 2, "F"),
    Some(ValueOutOfRange("F")),
  )
}

///|
/// A synthetic Resource with a Number(12,2), a Number(16,2) and a
/// Number(15,0); no real org.
fn number_observation() -> (CatalogObservation, CatalogObservationBinding) {
  let listing_body =
    #|{"sobjects":[{"name":"Order__c","queryable":true,"createable":true,"updateable":true}]}
  let listing = project_resource_listing(@utf8.encode(listing_body), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_resources: 10,
    max_selected: 10,
    max_name_units: 100,
  }).unwrap()
  let sync = begin_catalog_sync(listing)
  let describe_body =
    #|{"name":"Order__c","queryable":true,"createable":true,"updateable":true,"fields":[
    #|{"name":"Id","type":"id","nillable":false},
    #|{"name":"Amount__c","type":"double","precision":12,"scale":2,"nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true},
    #|{"name":"Units__c","type":"double","precision":15,"scale":0,"nillable":false,"defaultedOnCreate":false,"createable":true,"updateable":true},
    #|{"name":"Wide__c","type":"double","precision":16,"scale":2,"nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true}]}
  catalog_sync_describe(sync, "Order__c", @utf8.encode(describe_body), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 10,
    max_name_units: 100,
  }).unwrap()
  finish_catalog_sync(sync).unwrap()
  let binding = observation_test_binding()
  let digest = match catalog_sync_outcome(sync, "Order__c") {
    Some(Described(resource)) => resource.response_sha256
    _ => abort("expected described Order__c")
  }
  let observation = prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [Some(digest)],
    8192,
  ).unwrap()
  (observation, binding)
}

///|
fn number_read_plan() -> ReadProjection {
  let (observation, binding) = number_observation()
  prepare_read_projection(
    observation,
    binding,
    "Order__c",
    ["Id", "Amount__c", "Units__c"],
    256,
  ).unwrap()
}

///|
fn number_page(
  amount : String,
  units : String,
) -> Result[QueryPage, QueryPageIssue] {
  project_query_page(
    @utf8.encode(
      "{\"totalSize\":1,\"done\":true,\"records\":[{\"Id\":\"a01A\",\"Amount__c\":" +
      amount +
      ",\"Units__c\":" +
      units +
      "}]}",
    ),
    number_read_plan(),
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
fn decimal_cell(page : QueryPage, column : Int) -> String? {
  match query_page_cell(page, 0, column) {
    Some({ value: @admitted.Decimal(value), .. }) =>
      Some(value.coefficient + "e-" + value.scale.to_string())
    _ => None
  }
}

///|
test "a Number reply is admitted as its declared decimal, exponent form included" {
  // Beyond binary64's exact integers, and in the provider's exponent form.
  let page = number_page("1234567890.12", "1.2345678E7").unwrap()
  assert_eq(decimal_cell(page, 1), Some("123456789012e-2"))
  assert_eq(decimal_cell(page, 2), Some("12345678e-0"))
  let largest = number_page("-9999999999.99", "999999999999999").unwrap()
  assert_eq(decimal_cell(largest, 1), Some("-999999999999e-2"))
  assert_eq(decimal_cell(largest, 2), Some("999999999999999e-0"))
  let null = number_page("null", "0").unwrap()
  assert_true(query_page_cell(null, 0, 1).unwrap().value is @admitted.Null)
  // A Number above precision 15 is not readable.
  let (observation, binding) = number_observation()
  assert_true(
    prepare_read_projection(observation, binding, "Order__c", ["Wide__c"], 256)
    is Err(UnsupportedReadType("Wide__c")),
  )
}

///|
test "a Number reply outside its decimal is a typed violation without the value" {
  let plan = number_read_plan()
  let violation = fn(amount : String) {
    query_page_value_violation(number_page(amount, "1").unwrap_err(), plan)
  }
  let expect = fn(kind : String) {
    Some({
      resource: "Order__c",
      field: "Amount__c",
      expected_type: "decimal",
      kind,
    })
  }
  assert_eq(violation("12.345"), expect("scale"))
  assert_eq(violation("1.2345E-1"), expect("scale"))
  assert_eq(violation("12345678901"), expect("range"))
  assert_eq(violation("1E11"), expect("range"))
  // Text is not a Number reply, even in the decimal's own spelling.
  assert_eq(violation("\"12.50\""), expect("type"))
  assert_eq(violation("true"), expect("type"))
  assert_eq(
    query_page_value_violation(number_page("1", "null").unwrap_err(), plan).map(value => {
        (value.field, value.kind)
      },
    ),
    Some(("Units__c", "null")),
  )
  assert_false(
    query_value_violation_json(violation("12.345").unwrap()).contains("12"),
  )
}

///|
fn number_write_body(body : String) -> Result[WriteBody, WriteBodyIssue] {
  let (observation, binding) = number_observation()
  prepare_write_body(
    prepare_write_projection(
      observation,
      binding,
      "Order__c",
      WriteUpdateById,
      ["Amount__c", "Units__c"],
      2,
    ).unwrap(),
    @utf8.encode(body),
    { max_bytes: 1000, max_nodes: 20, max_depth: 2, },
  )
}

///|
test "an approved decimal is sent as the same number text, never through binary64" {
  let body = number_write_body(
    "{\"Units__c\":\"999999999999999\",\"Amount__c\":\"1234567890.12\"}",
  ).unwrap()
  // Fixed expectations: the provider body spells the same digits as JSON
  // numbers; the ActQL row keeps the decimal text.
  assert_eq(
    write_body_json(body),
    "{\"Amount__c\":1234567890.12,\"Units__c\":999999999999999}",
  )
  assert_eq(
    write_body_value_json(body),
    "{\"Amount__c\":\"1234567890.12\",\"Units__c\":\"999999999999999\"}",
  )
  assert_eq(
    write_body_json(
      number_write_body("{\"Units__c\":\"0\",\"Amount__c\":\"-0.10\"}").unwrap(),
    ),
    "{\"Amount__c\":-0.10,\"Units__c\":0}",
  )
  let refused = fn(amount : String) {
    number_write_body("{\"Units__c\":\"1\",\"Amount__c\":" + amount + "}").unwrap_err()
  }
  // Not the canonical text of decimal(12,2), a binary64 number, too many
  // integer digits.
  for amount in ["\"12.5\"", "\"1.25E1\"", "12.5", "\"-0.00\""] {
    assert_eq(refused(amount), InvalidValue("Amount__c"))
  }
  // A digit beyond the scale is refused, never rounded.
  assert_eq(refused("\"12.505\""), ValueBeyondScale("Amount__c"))
  assert_eq(refused("\"12345678901.00\""), ValueOutOfRange("Amount__c"))
  // A Number above precision 15 is not writable.
  let (observation, binding) = number_observation()
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

///|
test "the Preview states the decimal row; the request sends its number text" {
  let body = number_write_body("{\"Units__c\":\"3\",\"Amount__c\":\"12.50\"}").unwrap()
  let request = prepare_single_write_request(
    body,
    "v62.0",
    RecordId("a01000000000001"),
    write_request_test_limits(),
  ).unwrap()
  assert_eq(
    single_write_request_body(request),
    "{\"Amount__c\":12.50,\"Units__c\":3}",
  )
  assert_eq(
    single_write_request_value(request),
    "{\"Amount__c\":\"12.50\",\"Units__c\":\"3\"}",
  )
  // The target's current Number reply is read as the same decimal.
  let observed = prepare_target_observation(
    request,
    200,
    @utf8.encode(
      "{\"Id\":\"a01000000000001AAA\",\"Amount__c\":1.2345E3,\"Units__c\":7}",
    ),
    target_observation_test_limits(),
  ).unwrap()
  assert_eq(
    target_observation_before_value_wire(observed),
    "{\"Amount__c\":\"1234.50\",\"Units__c\":\"7\"}",
  )
  let row = prepare_observed_target_preview_row(request, observed, 1024).unwrap()
  assert_eq(
    target_preview_row_after_wire(row),
    "{\"Amount__c\":\"12.50\",\"Units__c\":\"3\"}",
  )
  assert_eq(
    target_preview_row_changes_wire(row),
    target_preview_row_after_wire(row),
  )
  // An observed value outside the decimal is not a valid observation.
  assert_true(
    prepare_target_observation(
      request,
      200,
      @utf8.encode(
        "{\"Id\":\"a01000000000001AAA\",\"Amount__c\":1.005,\"Units__c\":7}",
      ),
      target_observation_test_limits(),
    )
    is Err(InvalidRecord),
  )
  // A Preview recovered from the approved ActQL row rebuilds the same
  // provider request.
  let recovered = recover_single_write_request(
    body.projection,
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

///|
test "a Collections row sends the same decimal number text" {
  let rows : Array[WriteCollectionItem] = [
    {
      row_preview_cid: collection_request_test_cid("1"),
      body: number_write_body("{\"Units__c\":\"3\",\"Amount__c\":\"12.50\"}").unwrap(),
      target: RecordId("a01000000000001"),
    },
    {
      row_preview_cid: collection_request_test_cid("2"),
      body: number_write_body(
        "{\"Units__c\":\"999999999999999\",\"Amount__c\":\"-0.01\"}",
      ).unwrap(),
      target: RecordId("a01000000000002"),
    },
  ]
  let request = prepare_continue_write_collection(
    rows,
    "v62.0",
    collection_request_test_limits(),
  ).unwrap()
  let body = write_collection_request_body(request)
  assert_true(
    body.contains(
      "\"Amount__c\":12.50,\"Id\":\"a01000000000001\",\"Units__c\":3,",
    ),
  )
  assert_true(
    body.contains(
      "\"Amount__c\":-0.01,\"Id\":\"a01000000000002\",\"Units__c\":999999999999999,",
    ),
  )
}
