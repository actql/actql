///|
/// A synthetic Resource with a date and a datetime field; no real org.
fn temporal_observation() -> (CatalogObservation, CatalogObservationBinding) {
  let listing_body =
    #|{"sobjects":[{"name":"Event__c","queryable":true,"createable":true,"updateable":true}]}
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
    #|{"name":"Event__c","queryable":true,"createable":true,"updateable":true,"fields":[
    #|{"name":"Id","type":"id","nillable":false},
    #|{"name":"Due_On__c","type":"date","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true},
    #|{"name":"Starts_At__c","type":"datetime","nillable":false,"defaultedOnCreate":false,"createable":true,"updateable":true},
    #|{"name":"Opens_At__c","type":"time","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true}]}
  catalog_sync_describe(sync, "Event__c", @utf8.encode(describe_body), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 10,
    max_name_units: 100,
  }).unwrap()
  finish_catalog_sync(sync).unwrap()
  let binding = observation_test_binding()
  let digest = match catalog_sync_outcome(sync, "Event__c") {
    Some(Described(resource)) => resource.response_sha256
    _ => abort("expected described Event__c")
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
fn temporal_read_plan() -> ReadProjection {
  let (observation, binding) = temporal_observation()
  prepare_read_projection(
    observation,
    binding,
    "Event__c",
    ["Id", "Due_On__c", "Starts_At__c"],
    256,
  ).unwrap()
}

///|
fn temporal_page(body : String) -> Result[QueryPage, QueryPageIssue] {
  project_query_page(@utf8.encode(body), temporal_read_plan(), "v62.0", {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_rows: 4,
    max_locator_units: 128,
  })
}

///|
fn temporal_record(due : String, starts : String) -> String {
  "{\"totalSize\":1,\"done\":true,\"records\":[{\"Id\":\"a01A\",\"Due_On__c\":" +
  due +
  ",\"Starts_At__c\":" +
  starts +
  "}]}"
}

///|
test "a Salesforce date and UTC datetime are read as the same date and instant" {
  let page = temporal_page(
    temporal_record("\"2024-05-22\"", "\"2012-07-12T17:49:01.123+0000\""),
  ).unwrap()
  // Fixed expectations: the date as it is; the `+0000` instant ending in Z.
  assert_true(
    query_page_cell(page, 0, 1).unwrap().value is @admitted.Date("2024-05-22"),
  )
  assert_true(
    query_page_cell(page, 0, 2).unwrap().value
    is @admitted.Timestamp("2012-07-12T17:49:01.123Z"),
  )
  // A null date stays null.
  let nulls = temporal_page(
    temporal_record("null", "\"1700-01-01T00:00:00.000+0000\""),
  ).unwrap()
  assert_true(query_page_cell(nulls, 0, 1).unwrap().value is @admitted.Null)
  assert_true(
    query_page_cell(nulls, 0, 2).unwrap().value
    is @admitted.Timestamp("1700-01-01T00:00:00.000Z"),
  )
  // `time` has no ActQL type: a read of it is refused before any request.
  let (observation, binding) = temporal_observation()
  assert_true(
    prepare_read_projection(
      observation,
      binding,
      "Event__c",
      ["Opens_At__c"],
      256,
    )
    is Err(UnsupportedReadType("Opens_At__c")),
  )
}

///|
test "a datetime in any other spelling is a typed violation, never converted" {
  let plan = temporal_read_plan()
  for
    starts in [
      // Another offset is not converted to UTC.
      "\"2012-07-12T17:49:01.123+0900\"", "\"2012-07-12T17:49:01.123-0000\"", "\"2012-07-12T17:49:01.123+00:00\"",
      // The ActQL spelling is not the documented reply.
       "\"2012-07-12T17:49:01.123Z\"",
      // Other precisions and local forms are not rounded or completed.
       "\"2012-07-12T17:49:01+0000\"", "\"2012-07-12T17:49:01.1234+0000\"", "\"2012-07-12T17:49:01.123\"",
      "\"2012-02-30T17:49:01.123+0000\"", "\"2012-07-12 17:49:01.123+0000\"",
    ] {
    let issue = temporal_page(temporal_record("\"2024-05-22\"", starts)).unwrap_err()
    assert_true(
      issue
      is ValueAdmission(
        "Starts_At__c",
        @admitted.ValueIssue(@admitted.InvalidTimestamp, ..)
      ),
    )
    let violation = query_page_value_violation(issue, plan).unwrap()
    assert_eq(violation, {
      resource: "Event__c",
      field: "Starts_At__c",
      expected_type: "timestamp",
      kind: "format",
    })
    // The violation never carries the value.
    assert_false(query_value_violation_json(violation).contains("2012"))
  }
  assert_eq(
    query_value_violation_json(
      query_page_value_violation(
        temporal_page(
          temporal_record("\"2024-05-22\"", "\"2012-07-12T17:49:01.123Z\""),
        ).unwrap_err(),
        plan,
      ).unwrap(),
    ),
    "{\"expected_type\":\"timestamp\",\"field\":\"Starts_At__c\",\"kind\":\"format\",\"resource\":\"Event__c\"}",
  )
}

///|
test "date type and null violations are typed; budget failures are not violations" {
  let plan = temporal_read_plan()
  let violation = fn(due : String, starts : String) {
    query_page_value_violation(
      temporal_page(temporal_record(due, starts)).unwrap_err(),
      plan,
    )
  }
  let starts = "\"2012-07-12T17:49:01.000+0000\""
  for due in ["\"2024-02-30\"", "\"2024-5-22\"", "\"2024-05-22T00:00:00Z\""] {
    assert_eq(violation(due, starts).map(value => value.kind), Some("format"))
  }
  assert_eq(
    violation("20240522", starts).map(value => (value.field, value.kind)),
    Some(("Due_On__c", "type")),
  )
  assert_eq(
    violation("\"2024-05-22\"", "null").map(value => value.kind),
    Some("null"),
  )
  assert_eq(
    violation("\"2024-05-22\"", "1342115341000").map(value => value.kind),
    Some("type"),
  )
  // Over the page budget: not a value violation.
  let over = project_query_page(
    @utf8.encode(temporal_record("\"2024-05-22\"", starts)),
    plan,
    "v62.0",
    {
      max_bytes: 4096,
      max_nodes: 5,
      max_depth: 10,
      max_rows: 4,
      max_locator_units: 128,
    },
  ).unwrap_err()
  assert_eq(over, BudgetExceeded)
  assert_eq(query_page_value_violation(over, plan), None)
}

///|
fn temporal_write_projection(
  operation : WriteOperation,
  fields : Array[String],
) -> WriteProjection {
  let (observation, binding) = temporal_observation()
  prepare_write_projection(
    observation,
    binding,
    "Event__c",
    operation,
    fields,
    fields.length(),
  ).unwrap()
}

///|
fn temporal_body(body : String) -> Result[WriteBody, WriteBodyIssue] {
  prepare_write_body(
    temporal_write_projection(WriteUpdateById, ["Due_On__c", "Starts_At__c"]),
    @utf8.encode(body),
    { max_bytes: 1000, max_nodes: 20, max_depth: 2, },
  )
}

///|
test "an approved date and whole-second timestamp are sent as they are" {
  let body = temporal_body(
    "{\"Starts_At__c\":\"2024-05-22T09:30:00.000Z\",\"Due_On__c\":\"2024-05-22\"}",
  ).unwrap()
  assert_eq(
    write_body_json(body),
    "{\"Due_On__c\":\"2024-05-22\",\"Starts_At__c\":\"2024-05-22T09:30:00.000Z\"}",
  )
  // The documented range bounds are sent.
  assert_true(
    temporal_body(
      "{\"Due_On__c\":\"1700-01-01\",\"Starts_At__c\":\"4000-12-31T00:00:00.000Z\"}",
    )
    is Ok(_),
  )
  assert_true(
    temporal_body(
      "{\"Due_On__c\":\"4000-12-31\",\"Starts_At__c\":\"1700-01-01T00:00:00.000Z\"}",
    )
    is Ok(_),
  )
  // A nullable date may be cleared.
  assert_eq(
    write_body_json(
      temporal_body(
        "{\"Due_On__c\":null,\"Starts_At__c\":\"2024-05-22T09:30:00.000Z\"}",
      ).unwrap(),
    ),
    "{\"Due_On__c\":null,\"Starts_At__c\":\"2024-05-22T09:30:00.000Z\"}",
  )
  // `time` has no ActQL type and is not writable.
  let (observation, binding) = temporal_observation()
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "Event__c",
      WriteUpdateById,
      ["Opens_At__c"],
      1,
    )
    is Err(UnsupportedWriteType("Opens_At__c")),
  )
}

///|
test "a written value outside the contract is refused before sending, never rounded" {
  let date = "\"2024-05-22\""
  let at = "\"2024-05-22T09:30:00.000Z\""
  let body = fn(due : String, starts : String) {
    temporal_body("{\"Due_On__c\":" + due + ",\"Starts_At__c\":" + starts + "}")
  }
  // A nonzero millisecond part is refused, not rounded or dropped.
  for starts in ["\"2024-05-22T09:30:00.001Z\"", "\"2024-05-22T09:30:00.999Z\""] {
    assert_eq(
      body(date, starts).unwrap_err(),
      SubsecondTimestamp("Starts_At__c"),
    )
  }
  // Outside Salesforce's documented range.
  for starts in ["\"1699-12-31T23:59:59.000Z\"", "\"4000-12-31T00:00:01.000Z\""] {
    assert_eq(body(date, starts).unwrap_err(), ValueOutOfRange("Starts_At__c"))
  }
  for due in ["\"1699-12-31\"", "\"4001-01-01\""] {
    assert_eq(body(due, at).unwrap_err(), ValueOutOfRange("Due_On__c"))
  }
  // Offsets, the provider's reply spelling, and other precisions are not
  // converted: only the ActQL timestamp is written.
  for
    starts in [
      "\"2024-05-22T09:30:00.000+0000\"", "\"2024-05-22T18:30:00.000+09:00\"", "\"2024-05-22T09:30:00Z\"",
      "\"2024-05-22T09:30:00\"", "\"2024-02-30T09:30:00.000Z\"", "1716370200000",
    ] {
    assert_eq(body(date, starts).unwrap_err(), InvalidValue("Starts_At__c"))
  }
  for due in ["\"2024-02-30\"", "\"2024-05-22T00:00:00.000Z\"", "20240522"] {
    assert_eq(body(due, at).unwrap_err(), InvalidValue("Due_On__c"))
  }
  assert_eq(body(date, "null").unwrap_err(), NullNotAllowed("Starts_At__c"))
  // Each refusal is typed by field, type and kind, without the value.
  let projection = temporal_write_projection(WriteUpdateById, [
    "Due_On__c", "Starts_At__c",
  ])
  let refusal = fn(issue : WriteBodyIssue) {
    write_body_value_refusal_json(issue, projection)
  }
  assert_eq(
    refusal(body(date, "\"2024-05-22T09:30:00.001Z\"").unwrap_err()),
    Some(
      "{\"expected_type\":\"timestamp\",\"field\":\"Starts_At__c\",\"kind\":\"precision\",\"resource\":\"Event__c\"}",
    ),
  )
  assert_eq(
    refusal(body("\"4001-01-01\"", at).unwrap_err()),
    Some(
      "{\"expected_type\":\"date\",\"field\":\"Due_On__c\",\"kind\":\"range\",\"resource\":\"Event__c\"}",
    ),
  )
  assert_eq(
    refusal(body(date, "\"2024-05-22T09:30:00\"").unwrap_err()),
    Some(
      "{\"expected_type\":\"timestamp\",\"field\":\"Starts_At__c\",\"kind\":\"format\",\"resource\":\"Event__c\"}",
    ),
  )
  assert_eq(refusal(BudgetExceeded), None)
  assert_eq(refusal(MissingField("Due_On__c")), None)
}

///|
test "an observed target datetime is read in UTC as the Preview's before value" {
  let projection = temporal_write_projection(WriteUpdateById, [
    "Due_On__c", "Starts_At__c",
  ])
  let body = prepare_write_body(
    projection,
    @utf8.encode(
      "{\"Due_On__c\":\"2024-05-23\",\"Starts_At__c\":\"2024-05-22T09:30:00.000Z\"}",
    ),
    { max_bytes: 1000, max_nodes: 20, max_depth: 2, },
  ).unwrap()
  let request = prepare_single_write_request(
    body,
    "v62.0",
    RecordId("a01000000000001"),
    write_request_test_limits(),
  ).unwrap()
  // The current value may carry milliseconds and any date in range of the
  // ActQL types; it is an observation, not a write.
  let observed = prepare_target_observation(
    request,
    200,
    @utf8.encode(
      "{\"Id\":\"a01000000000001AAA\",\"Due_On__c\":\"2024-05-22\",\"Starts_At__c\":\"2024-05-22T09:30:00.250+0000\"}",
    ),
    target_observation_test_limits(),
  ).unwrap()
  assert_eq(
    target_observation_before_value_wire(observed),
    "{\"Due_On__c\":\"2024-05-22\",\"Starts_At__c\":\"2024-05-22T09:30:00.250Z\"}",
  )
  // Another offset is not an observed UTC instant.
  assert_true(
    prepare_target_observation(
      request,
      200,
      @utf8.encode(
        "{\"Id\":\"a01000000000001AAA\",\"Due_On__c\":\"2024-05-22\",\"Starts_At__c\":\"2024-05-22T18:30:00.250+0900\"}",
      ),
      target_observation_test_limits(),
    )
    is Err(InvalidRecord),
  )
}

///|
test "the write capability states whole-second datetime writes" {
  let body = prepare_write_body(
    temporal_write_projection(WriteUpdateById, ["Due_On__c", "Starts_At__c"]),
    @utf8.encode(
      "{\"Due_On__c\":\"2024-05-23\",\"Starts_At__c\":\"2024-05-22T09:30:00.000Z\"}",
    ),
    { max_bytes: 1000, max_nodes: 20, max_depth: 2, },
  ).unwrap()
  let request = prepare_single_write_request(
    body,
    "v62.0",
    RecordId("a01000000000001"),
    write_request_test_limits(),
  ).unwrap()
  let evidence = prepare_write_capability_evidence(
    request,
    "sha256:" + "e".repeat(64),
    SerialRows,
    100000,
  ).unwrap()
  assert_true(
    evidence.body.contains(
      "\"name\":\"Starts_At__c\",\"native_type\":\"datetime\"",
    ),
  )
  assert_true(
    evidence.body.contains(
      "\"updateable\":true,\"write_timestamp_precision\":\"second\"}",
    ),
  )
  // Only the datetime field states it.
  assert_eq(evidence.body.split("write_timestamp_precision").count(), 2)
}
