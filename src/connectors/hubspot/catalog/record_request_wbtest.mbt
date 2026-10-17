///|
fn request_limits() -> RecordRequestLimits {
  {
    max_rows: 100,
    max_properties: 100,
    max_trace_bytes: 100,
    max_body_bytes: 10000,
    max_body_nodes: 1000,
    max_body_depth: 20,
  }
}

///|
fn request_catalog() -> PropertyCatalog {
  catalog(
    (
      #|{"results":[{"name":"name","type":"string","fieldType":"text","calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"external_key","type":"string","fieldType":"text","hasUniqueValue":true,"calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"number_key","type":"number","fieldType":"number","hasUniqueValue":true,"calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"domain","type":"string","fieldType":"text","hasUniqueValue":false,"calculated":false,"modificationMetadata":{"readOnlyValue":false}}]}
    ),
  )
}

///|
fn request_body(
  catalog : PropertyCatalog,
  name? : String = "original",
) -> WriteBody {
  // The fixture's value is JSON-escaped by the same public string encoder.
  let wire = ({ "name": name.to_json() } : Json).stringify()
  prepare_write_body(catalog, ["name"], @utf8.encode(wire), write_limits()).unwrap()
}

///|
fn request_target(
  catalog : PropertyCatalog,
  key : String,
  wire : String,
) -> RecordTarget {
  prepare_record_target(catalog, key, @utf8.encode(wire), write_limits()).unwrap()
}

///|
test "batch create embeds complete encoder documents and exact independent trace values" {
  let catalog = request_catalog()
  let body = request_body(catalog)
  let request = prepare_record_batch_request(
    catalog,
    Create,
    [{ body, target: None, trace_id: "original-1", }],
    request_limits(),
  ).unwrap()
  assert_eq(
    record_batch_request_body(request),
    "{\"inputs\":[{\"objectWriteTraceId\":\"original-1\",\"properties\":{\"name\":\"original\"}}]}",
  )
  assert_eq(record_batch_request_count(request), 1)
  assert_eq(record_batch_request_object_type(request), "companies")
  assert_eq(
    record_batch_request_input(request, 0).unwrap().trace_id,
    "original-1",
  )
  assert_true(record_batch_request_input(request, -1) is None)
  assert_true(record_batch_request_input(request, 1) is None)
}

///|
test "batch update keeps record ids as exact strings without numeric conversion" {
  let catalog = request_catalog()
  let request = prepare_record_batch_request(
    catalog,
    Update,
    [
      {
        body: request_body(catalog),
        target: Some(request_target(catalog, "id", "\"9007199254740993\"")),
        trace_id: "original-update",
      },
    ],
    request_limits(),
  ).unwrap()
  assert_eq(
    record_batch_request_body(request),
    "{\"inputs\":[{\"id\":\"9007199254740993\",\"objectWriteTraceId\":\"original-update\",\"properties\":{\"name\":\"original\"}}]}",
  )
}

///|
test "upsert uses only positively observed unique metadata and the original typed selector" {
  let catalog = request_catalog()
  let target = request_target(catalog, "external_key", "\"a/b?é\"")
  assert_eq(target.value_wire, "\"a/b?é\"")
  let request = prepare_record_batch_request(
    catalog,
    Upsert("external_key"),
    [{ body: request_body(catalog), target: Some(target), trace_id: "upsert", }],
    request_limits(),
  ).unwrap()
  assert_eq(
    record_batch_request_body(request),
    "{\"inputs\":[{\"id\":\"a/b?é\",\"idProperty\":\"external_key\",\"objectWriteTraceId\":\"upsert\",\"properties\":{\"name\":\"original\"}}]}",
  )
  assert_true(
    prepare_record_target(
      catalog,
      "domain",
      @utf8.encode("\"same.example\""),
      write_limits(),
    )
    is Err(Property(UniqueKeyUnconfirmed("domain"))),
  )
}

///|
test "unique numeric selectors are exact Common decimal values not binary64 or sampled strings" {
  let catalog = request_catalog()
  let target = request_target(
    catalog, "number_key", "\"9007199254740993.0100000000\"",
  )
  assert_eq(target.provider_value, "9007199254740993.0100000000")
  assert_eq(target.value_wire, "\"9007199254740993.0100000000\"")
  assert_true(
    prepare_record_target(
      catalog,
      "number_key",
      @utf8.encode("9007199254740993.01"),
      write_limits(),
    )
    is Err(Value(ValueAdmission("number_key", _))),
  )
}

///|
test "target null empty malformed numeric record ids and nonunique fields never name a record" {
  let catalog = request_catalog()
  for wire in ["null", "\"\"", "42", "[]", "{}", "true", "\"x\" trailing"] {
    assert_true(
      prepare_record_target(catalog, "id", @utf8.encode(wire), write_limits())
      is Err(_),
    )
  }
  assert_true(
    prepare_record_target(
      catalog,
      "external_key",
      @utf8.encode("null"),
      write_limits(),
    )
    is Err(InvalidTarget),
  )
  assert_true(
    prepare_record_target(
      catalog,
      "name",
      @utf8.encode("\"x\""),
      write_limits(),
    )
    is Err(Property(UniqueKeyUnconfirmed("name"))),
  )
  assert_true(
    prepare_record_target(
      catalog,
      "missing",
      @utf8.encode("\"x\""),
      write_limits(),
    )
    is Err(Property(PropertyUnconfirmed("missing"))),
  )
}

///|
test "request operation cannot borrow a target of another key or silently discard one" {
  let catalog = request_catalog()
  let body = request_body(catalog)
  let by_id = request_target(catalog, "id", "\"1\"")
  let by_unique = request_target(catalog, "external_key", "\"one\"")
  let input = { body, target: Some(by_id), trace_id: "x", }
  assert_true(
    prepare_record_batch_request(catalog, Create, [input], request_limits())
    is Err(UnexpectedTarget),
  )
  assert_true(
    prepare_record_batch_request(
      catalog,
      Update,
      [{ ..input, target: None, }],
      request_limits(),
    )
    is Err(MissingTarget),
  )
  assert_true(
    prepare_record_batch_request(
      catalog,
      Update,
      [{ ..input, target: Some(by_unique), }],
      request_limits(),
    )
    is Err(ForeignTargetKey),
  )
  assert_true(
    prepare_record_batch_request(
      catalog,
      Upsert("external_key"),
      [input],
      request_limits(),
    )
    is Err(ForeignTargetKey),
  )
  assert_true(
    prepare_record_batch_request(
      catalog,
      Upsert("id"),
      [input],
      request_limits(),
    )
    is Err(ForeignTargetKey),
  )
}

///|
test "foreign or changed catalog bodies and selectors cannot enter the original batch" {
  let original = request_catalog()
  let other = write_catalog()
  let by_id = request_target(original, "id", "\"1\"")
  assert_true(
    prepare_record_batch_request(
      original,
      Update,
      [{ body: request_body(other), target: Some(by_id), trace_id: "x", }],
      request_limits(),
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    prepare_record_batch_request(
      original,
      Update,
      [
        {
          body: request_body(original),
          target: Some(request_target(other, "id", "\"1\"")),
          trace_id: "x",
        },
      ],
      request_limits(),
    )
    is Err(ForeignCatalog),
  )
}

///|
test "duplicate targets or traces are refused instead of being resent or silently dropped" {
  let catalog = request_catalog()
  let input = {
    body: request_body(catalog),
    target: Some(request_target(catalog, "id", "\"1\"")),
    trace_id: "first",
  }
  assert_true(
    prepare_record_batch_request(
      catalog,
      Update,
      [input, { ..input, trace_id: "second", }],
      request_limits(),
    )
    is Err(DuplicateTarget),
  )
  assert_true(
    prepare_record_batch_request(
      catalog,
      Create,
      [{ ..input, target: None, }, { ..input, target: None, }],
      request_limits(),
    )
    is Err(DuplicateTrace),
  )
  assert_true(
    prepare_record_batch_request(
      catalog,
      Create,
      [{ ..input, target: None, trace_id: "", }],
      request_limits(),
    )
    is Err(InvalidTrace),
  )
}

///|
test "caller arrays cannot replace retained request members after preparation" {
  let catalog = request_catalog()
  let input = {
    body: request_body(catalog),
    target: None,
    trace_id: "original",
  }
  let inputs = [input]
  let request = prepare_record_batch_request(
    catalog,
    Create,
    inputs,
    request_limits(),
  ).unwrap()
  let original = record_batch_request_body(request)
  inputs[0] = { ..input, trace_id: "changed", }
  inputs.push(input)
  assert_eq(record_batch_request_body(request), original)
  assert_eq(record_batch_request_count(request), 1)
  assert_eq(
    record_batch_request_input(request, 0).unwrap().trace_id,
    "original",
  )
}

///|
test "complete document bytes nodes and depth all count in the containing request" {
  let catalog = request_catalog()
  let input = {
    body: request_body(catalog, name="é"),
    target: None,
    trace_id: "one",
  }
  let baseline = prepare_record_batch_request(
    catalog,
    Create,
    [input],
    request_limits(),
  ).unwrap()
  let bytes = @utf8.encode(record_batch_request_body(baseline)).length()
  assert_true(
    prepare_record_batch_request(catalog, Create, [input], {
      ..request_limits(),
      max_body_bytes: bytes,
    })
    is Ok(_),
  )
  assert_true(
    prepare_record_batch_request(catalog, Create, [input], {
      ..request_limits(),
      max_body_bytes: bytes - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_batch_request(catalog, Create, [input], {
      ..request_limits(),
      max_body_nodes: 5,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_batch_request(catalog, Create, [input], {
      ..request_limits(),
      max_body_depth: 3,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_batch_request(catalog, Create, [input], {
      ..request_limits(),
      max_trace_bytes: 2,
    })
    is Err(InvalidTrace),
  )
}

///|
test "batch bound is at most the provider hundred and no empty or partial batch escapes" {
  let catalog = request_catalog()
  let input = { body: request_body(catalog), target: None, trace_id: "one", }
  assert_true(
    prepare_record_batch_request(catalog, Create, [], request_limits())
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_batch_request(catalog, Create, [input], {
      ..request_limits(),
      max_rows: 101,
    })
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_record_batch_request(catalog, Create, [input], {
      ..request_limits(),
      max_rows: 0,
    })
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_record_batch_request(catalog, Create, [input], {
      ..request_limits(),
      max_body_nodes: 0,
    })
    is Err(InvalidLimits),
  )
}

///|
test "request current recheck preserves all original metadata rather than only target property" {
  let catalog = request_catalog()
  let input = { body: request_body(catalog), target: None, trace_id: "one", }
  let request = prepare_record_batch_request(
    catalog,
    Create,
    [input],
    request_limits(),
  ).unwrap()
  assert_eq(
    recheck_record_batch_request(request, request_catalog(), 100),
    Ok(()),
  )
  assert_eq(
    recheck_record_batch_request(request, write_catalog(), 100),
    Err(ForeignCatalog),
  )
  assert_eq(
    recheck_record_batch_request(request, catalog, 0),
    Err(InvalidLimits),
  )
}

///|
test "target preparation validates its whole supplied limit contract and bounds key bytes before lookup" {
  let catalog = request_catalog()
  for
    limits in [
      { ..write_limits(), max_input_bytes: 0, },
      { ..write_limits(), max_fields: 0, },
      { ..write_limits(), max_name_bytes: 0, },
      { ..write_limits(), max_comparison_work: 0, },
    ] {
    assert_true(
      prepare_record_target(catalog, "id", @utf8.encode("\"1\""), limits)
      is Err(InvalidLimits),
    )
  }
  assert_true(
    prepare_record_target(catalog, "id", @utf8.encode("\"1\""), {
      ..write_limits(),
      max_name_bytes: 2,
    })
    is Ok(_),
  )
  assert_true(
    prepare_record_target(catalog, "id", @utf8.encode("\"1\""), {
      ..write_limits(),
      max_name_bytes: 1,
    })
    is Err(BudgetExceeded),
  )
}
