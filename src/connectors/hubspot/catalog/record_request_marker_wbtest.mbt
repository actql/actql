///|
fn marker_catalog() -> PropertyCatalog {
  catalog(
    (
      #|{"results":[{"name":"amount","type":"number","fieldType":"number","calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"actql_request_id","type":"string","fieldType":"text","hasUniqueValue":false,"calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"readonly","type":"string","fieldType":"text","calculated":false,"modificationMetadata":{"readOnlyValue":true}},{"name":"external_key","type":"string","fieldType":"text","hasUniqueValue":true,"calculated":false,"modificationMetadata":{"readOnlyValue":false}}]}
    ),
  )
}

///|
fn marked_input(
  catalog : PropertyCatalog,
  operation : RecordWriteOperation,
  trace : String,
) -> RecordWriteInput {
  let body = prepare_write_body(
    catalog,
    ["amount"],
    b"{\"amount\":\"9007199254740993.0100000000\"}",
    write_limits(),
  ).unwrap()
  let target = match operation {
    Create => None
    Update => Some(request_target(catalog, "id", "\"9007199254740993\""))
    Upsert(key) => Some(request_target(catalog, key, "\"original-key\""))
  }
  { body, target, trace_id: trace, }
}

///|
test "request marker is original physical metadata and does not change the business value or target" {
  let catalog = marker_catalog()
  let marker = prepare_record_request_marker(
    catalog,
    "actql_request_id",
    "original-request-1",
    write_limits(),
  ).unwrap()
  for operation in [Create, Update, Upsert("external_key")] {
    let input = marked_input(catalog, operation, "correlation-not-idempotency")
    let old = prepare_record_batch_request(
      catalog,
      operation,
      [input],
      request_limits(),
    ).unwrap()
    let marked = prepare_marked_record_batch_request(
      catalog,
      operation,
      [input],
      marker,
      request_limits(),
    ).unwrap()
    assert_true(record_batch_request_marker(old) is None)
    assert_eq(
      record_batch_request_marker(marked).unwrap().request_id,
      "original-request-1",
    )
    assert_true(
      record_batch_request_body(marked).contains(
        "\"actql_request_id\":\"original-request-1\"",
      ),
    )
    assert_true(!record_batch_request_body(old).contains("actql_request_id"))
    let retained = record_batch_request_input(marked, 0).unwrap()
    assert_eq(
      write_body_value_json(retained.body),
      "{\"amount\":\"9007199254740993.0100000000\"}",
    )
    assert_eq(
      retained.target.map(target => target.value_wire),
      input.target.map(target => target.value_wire),
    )
    assert_eq(retained.trace_id, "correlation-not-idempotency")
    assert_eq(record_batch_request_count(marked), 1)
  }
}

///|
test "one original physical batch marker covers every original item without replacing traces" {
  let catalog = marker_catalog()
  let marker = prepare_record_request_marker(
    catalog,
    "actql_request_id",
    "batch-1",
    write_limits(),
  ).unwrap()
  let request = prepare_marked_record_batch_request(
    catalog,
    Create,
    [
      marked_input(catalog, Create, "row-1"),
      marked_input(catalog, Create, "row-2"),
    ],
    marker,
    request_limits(),
  ).unwrap()
  assert_eq(
    record_batch_request_body(request),
    "{\"inputs\":[{\"objectWriteTraceId\":\"row-1\",\"properties\":{\"actql_request_id\":\"batch-1\",\"amount\":\"9007199254740993.0100000000\"}},{\"objectWriteTraceId\":\"row-2\",\"properties\":{\"actql_request_id\":\"batch-1\",\"amount\":\"9007199254740993.0100000000\"}}]}",
  )
  assert_eq(record_batch_request_count(request), 2)
}

///|
test "marker property requires positive original writable string metadata" {
  let catalog = marker_catalog()
  for property in ["id", "readonly", "amount", "missing"] {
    assert_true(
      prepare_record_request_marker(
        catalog,
        property,
        "request-1",
        write_limits(),
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_record_request_marker(
      catalog,
      "actql_request_id",
      "",
      write_limits(),
    )
    is Err(InvalidMarker),
  )
  assert_true(
    prepare_record_request_marker(catalog, "actql_request_id", "request-1", {
      ..write_limits(),
      max_input_bytes: 0,
    })
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_record_request_marker(catalog, "actql_request_id", "request-1", {
      ..write_limits(),
      max_input_bytes: 2,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "business values cannot overwrite or select the reserved physical marker property" {
  let original = marker_catalog()
  let marker = prepare_record_request_marker(
    original,
    "actql_request_id",
    "physical-request",
    write_limits(),
  ).unwrap()
  let body = prepare_write_body(
    original,
    ["actql_request_id"],
    b"{\"actql_request_id\":\"business-value\"}",
    write_limits(),
  ).unwrap()
  let input = { body, target: None, trace_id: "row-1", }
  assert_true(
    prepare_marked_record_batch_request(
      original,
      Create,
      [input],
      marker,
      request_limits(),
    )
    is Err(MarkerConflict),
  )
  let unique_catalog = catalog(
    (
      #|{"results":[{"name":"actql_request_id","type":"string","fieldType":"text","hasUniqueValue":true,"calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"amount","type":"number","fieldType":"number","calculated":false,"modificationMetadata":{"readOnlyValue":false}}]}
    ),
  )
  let unique_marker = prepare_record_request_marker(
    unique_catalog,
    "actql_request_id",
    "original-request",
    write_limits(),
  ).unwrap()
  let targeted = marked_input(
    unique_catalog,
    Upsert("actql_request_id"),
    "row-1",
  )
  assert_true(
    prepare_marked_record_batch_request(
      unique_catalog,
      Upsert("actql_request_id"),
      [targeted],
      unique_marker,
      request_limits(),
    )
    is Err(MarkerConflict),
  )
}

///|
test "foreign catalog and smaller complete-body ceiling refuse without marker truncation" {
  let original = marker_catalog()
  let marker = prepare_record_request_marker(
    original,
    "actql_request_id",
    "original-request",
    write_limits(),
  ).unwrap()
  let input = marked_input(original, Create, "row-1")
  assert_true(
    prepare_marked_record_batch_request(original, Create, [input], marker, {
      ..request_limits(),
      max_body_bytes: 80,
    })
    is Err(BudgetExceeded),
  )
  let foreign = catalog(
    (
      #|{"results":[{"name":"actql_request_id","type":"string","fieldType":"text","calculated":false,"modificationMetadata":{"readOnlyValue":false}}]}
    ),
  )
  let foreign_marker = prepare_record_request_marker(
    foreign,
    "actql_request_id",
    "original-request",
    write_limits(),
  ).unwrap()
  assert_true(
    prepare_marked_record_batch_request(
      original,
      Create,
      [input],
      foreign_marker,
      request_limits(),
    )
    is Err(ForeignCatalog),
  )
}
