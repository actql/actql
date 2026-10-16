///|
fn read_limits() -> RecordReadLimits {
  {
    max_rows: 100,
    max_properties: 100,
    max_columns: 10,
    max_request_bytes: 10000,
    max_request_nodes: 1000,
    max_request_depth: 20,
  }
}

///|
fn read_catalog() -> PropertyCatalog {
  catalog(
    (
      #|{"results":[{"name":"amount","type":"number","fieldType":"number"},{"name":"external_key","type":"string","fieldType":"text","hasUniqueValue":true},{"name":"hs_lastmodifieddate","type":"datetime","fieldType":"date"}]}
    ),
  )
}

///|
fn read_target(
  catalog : PropertyCatalog,
  key : String,
  value : String,
) -> RecordTarget {
  prepare_record_target(
    catalog,
    key,
    @utf8.encode(value.to_json().stringify()),
    write_limits(),
  ).unwrap()
}

///|
fn read_row(
  id : String,
  key? : String = "key",
  amount? : String = "9007199254740993.01",
  updated? : String = "2026-10-17T00:00:00.000Z",
) -> Json {
  {
    "id": id.to_json(),
    "archived": false,
    "updatedAt": updated.to_json(),
    "properties": {
      "amount": amount.to_json(),
      "external_key": key.to_json(),
      "hs_lastmodifieddate": "2026-10-17T00:00:00.000Z",
    },
  }
}

///|
fn read_response(rows : Array[Json], status? : String = "COMPLETE") -> Bytes {
  @utf8.encode(
    ({ "status": status.to_json(), "results": rows.to_json() } : Json).stringify(),
  )
}

///|
fn read_projection(
  request : RecordReadRequest,
  response : Bytes,
) -> Result[RecordReadObservation, RecordReadIssue] {
  project_record_read_observation(
    request,
    response,
    page_limits(),
    10000,
    1000,
    20,
  )
}

///|
test "target read request preserves typed selectors and requests actual correlation properties" {
  let catalog = read_catalog()
  let request = prepare_record_read_request(
    catalog,
    [read_target(catalog, "external_key", "a/b?é")],
    ["amount"],
    read_limits(),
  ).unwrap()
  assert_eq(
    record_read_request_body(request),
    "{\"inputs\":[{\"id\":\"a/b?é\"}],\"idProperty\":\"external_key\",\"properties\":[\"amount\",\"external_key\"]}",
  )
  assert_eq(record_read_request_object_type(request), "companies")
  let by_id = prepare_record_read_request(
    catalog,
    [read_target(catalog, "id", "9007199254740993")],
    ["amount"],
    read_limits(),
  ).unwrap()
  assert_eq(
    record_read_request_body(by_id),
    "{\"inputs\":[{\"id\":\"9007199254740993\"}],\"properties\":[\"amount\"]}",
  )
}

///|
test "original record order wins over response order with exact decimal and modification observation" {
  let catalog = read_catalog()
  let targets = [
    read_target(catalog, "id", "9007199254740993"),
    read_target(catalog, "id", "2"),
  ]
  let names = ["amount", "hs_lastmodifieddate"]
  let request = prepare_record_read_request(
    catalog,
    targets,
    names,
    read_limits(),
  ).unwrap()
  names[0] = "foreign"
  targets.clear()
  let observation = read_projection(
    request,
    read_response([read_row("2", amount="0"), read_row("9007199254740993")]),
  ).unwrap()
  assert_eq(
    record_read_observation_wire(observation),
    "[{\"id\":\"9007199254740993\",\"updatedAt\":\"2026-10-17T00:00:00.000Z\",\"properties\":{\"amount\":\"9007199254740993.0100000000\",\"hs_lastmodifieddate\":\"2026-10-17T00:00:00.000Z\"}},{\"id\":\"2\",\"updatedAt\":\"2026-10-17T00:00:00.000Z\",\"properties\":{\"amount\":\"0.0000000000\",\"hs_lastmodifieddate\":\"2026-10-17T00:00:00.000Z\"}}]",
  )
}

///|
test "custom unique selectors correlate actual record ids independently from provider order" {
  let catalog = read_catalog()
  let request = prepare_record_read_request(
    catalog,
    [
      read_target(catalog, "external_key", "a"),
      read_target(catalog, "external_key", "b"),
    ],
    ["amount"],
    read_limits(),
  ).unwrap()
  let first = read_projection(
    request,
    read_response([read_row("2", key="b"), read_row("1", key="a")]),
  ).unwrap()
  let second = read_projection(
    request,
    read_response([read_row("1", key="a"), read_row("2", key="b")]),
  ).unwrap()
  assert_true(first.response_sha256 != second.response_sha256)
  assert_true(
    recheck_record_read_observation(first, second, 100, 10000) is Ok(_),
  )
}

///|
test "two record ids for one supposedly unique selector are not an arbitrary first match" {
  let catalog = read_catalog()
  let request = prepare_record_read_request(
    catalog,
    [
      read_target(catalog, "external_key", "a"),
      read_target(catalog, "external_key", "b"),
    ],
    ["amount"],
    read_limits(),
  ).unwrap()
  assert_true(
    read_projection(
      request,
      read_response([read_row("1", key="a"), read_row("2", key="a")]),
    )
    is Err(DuplicateRecord),
  )
  assert_true(
    read_projection(
      request,
      read_response([read_row("1", key="a"), read_row("2", key="foreign")]),
    )
    is Err(ForeignRecord),
  )
}

///|
test "missing incomplete pending cancelled and error responses never prove an absent target" {
  let catalog = read_catalog()
  let request = prepare_record_read_request(
    catalog,
    [read_target(catalog, "id", "1")],
    ["amount"],
    read_limits(),
  ).unwrap()
  assert_true(
    read_projection(request, read_response([])) is Err(IncompleteResponse),
  )
  for status in ["PENDING", "PROCESSING", "CANCELED", "COMPLETE "] {
    assert_true(
      read_projection(request, read_response([read_row("1")], status~))
      is Err(IncompleteResponse),
    )
  }
  for
    tail in [
      "\"errors\":[{}]", "\"errors\":null", "\"numErrors\":1", "\"numErrors\":\"0\"",
    ] {
    let body = "{\"status\":\"COMPLETE\",\"results\":[" +
      read_row("1").stringify() +
      "]," +
      tail +
      "}"
    assert_true(
      read_projection(request, @utf8.encode(body)) is Err(IncompleteResponse),
    )
  }
}

///|
test "foreign duplicated archived or untyped records retain their original refusal" {
  let catalog = read_catalog()
  let request = prepare_record_read_request(
    catalog,
    [read_target(catalog, "id", "1")],
    ["amount"],
    read_limits(),
  ).unwrap()
  assert_true(
    read_projection(request, read_response([read_row("foreign")]))
    is Err(ForeignRecord),
  )
  assert_true(
    read_projection(request, read_response([read_row("1", amount="NaN")]))
    is Err(Page(_)),
  )
  assert_true(
    read_projection(
      request,
      @utf8.encode(
        "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"1\",\"archived\":true,\"properties\":{\"amount\":\"0\"}}]}",
      ),
    )
    is Err(Page(ArchivedRecord)),
  )
  let two = prepare_record_read_request(
    catalog,
    [read_target(catalog, "id", "1"), read_target(catalog, "id", "2")],
    ["amount"],
    read_limits(),
  ).unwrap()
  assert_true(
    read_projection(two, read_response([read_row("1"), read_row("1")]))
    is Err(Page(DuplicateRecord("1"))),
  )
}

///|
test "required updatedAt cannot be missing malformed or an invalid calendar date" {
  let catalog = read_catalog()
  let request = prepare_record_read_request(
    catalog,
    [read_target(catalog, "id", "1")],
    ["amount"],
    read_limits(),
  ).unwrap()
  for updated in ["", "garbage", "2026-02-30T00:00:00.000Z"] {
    assert_true(
      read_projection(request, read_response([read_row("1", updated~)]))
      is Err(InvalidUpdatedAt),
    )
  }
  assert_true(
    read_projection(
      request,
      @utf8.encode(
        "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"1\",\"archived\":false,\"properties\":{\"amount\":\"0\"}}]}",
      ),
    )
    is Err(InvalidUpdatedAt),
  )
}

///|
test "actual changed id value modification time or original selection refuses equality" {
  let catalog = read_catalog()
  let request = prepare_record_read_request(
    catalog,
    [read_target(catalog, "external_key", "a")],
    ["amount"],
    read_limits(),
  ).unwrap()
  let original = read_projection(
    request,
    read_response([read_row("1", key="a")]),
  ).unwrap()
  for
    row in [
      read_row("2", key="a"),
      read_row("1", key="a", amount="2"),
      read_row("1", key="a", updated="2026-10-17T00:00:00.001Z"),
    ] {
    assert_true(
      recheck_record_read_observation(
        original,
        read_projection(request, read_response([row])).unwrap(),
        100,
        10000,
      )
      is Err(ChangedObservation),
    )
  }
  let different = prepare_record_read_request(
    catalog,
    [read_target(catalog, "external_key", "a")],
    [],
    read_limits(),
  ).unwrap()
  assert_true(
    recheck_record_read_observation(
      original,
      read_projection(different, read_response([read_row("1", key="a")])).unwrap(),
      100,
      10000,
    )
    is Err(ChangedObservation),
  )
}

///|
test "request bounds include implicit correlation columns and refuse mixed foreign or repeated selectors" {
  let catalog = read_catalog()
  let a = read_target(catalog, "id", "1")
  assert_true(
    prepare_record_read_request(catalog, [a, a], ["amount"], read_limits())
    is Err(DuplicateTarget),
  )
  assert_true(
    prepare_record_read_request(
      catalog,
      [a, read_target(catalog, "external_key", "a")],
      ["amount"],
      read_limits(),
    )
    is Err(ForeignTargetKey),
  )
  assert_true(
    prepare_record_read_request(read_catalog(), [], ["amount"], read_limits())
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_read_request(
      catalog,
      [a],
      ["amount", "amount"],
      read_limits(),
    )
    is Err(ForeignTargetKey),
  )
  assert_true(
    prepare_record_read_request(catalog, [a], ["id"], read_limits())
    is Err(ForeignTargetKey),
  )
  assert_true(
    prepare_record_read_request(catalog, [a], ["missing"], read_limits())
    is Err(Property(_)),
  )
  assert_true(
    prepare_record_read_request(
      catalog,
      [read_target(catalog, "external_key", "a")],
      ["amount"],
      { ..read_limits(), max_columns: 1, },
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_read_request(catalog, [a], ["amount"], {
      ..read_limits(),
      max_request_bytes: 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_read_request(catalog, [a], ["amount"], {
      ..read_limits(),
      max_rows: 101,
    })
    is Err(InvalidLimits),
  )
  let foreign = request_target(request_catalog(), "id", "\"1\"")
  assert_true(
    prepare_record_read_request(catalog, [foreign], ["amount"], read_limits())
    is Err(ForeignCatalog),
  )
}

///|
test "response output and complete equality each enforce their independent bounds" {
  let catalog = read_catalog()
  let request = prepare_record_read_request(
    catalog,
    [read_target(catalog, "id", "1")],
    ["amount"],
    read_limits(),
  ).unwrap()
  let bytes = read_response([read_row("1")])
  for (b, n, d) in [(1, 1000, 20), (10000, 1, 20), (10000, 1000, 1)] {
    assert_true(
      project_record_read_observation(request, bytes, page_limits(), b, n, d)
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    project_record_read_observation(
      request,
      bytes,
      { ..page_limits(), max_bytes: 1, },
      10000,
      1000,
      20,
    )
    is Err(Page(BudgetExceeded)),
  )
  let observed = read_projection(request, bytes).unwrap()
  let cost = record_read_request_body(request).length() * 2 +
    record_read_observation_wire(observed).length() * 2
  assert_true(
    recheck_record_read_observation(observed, observed, 100, cost) is Ok(_),
  )
  assert_true(
    recheck_record_read_observation(observed, observed, 100, cost - 1)
    is Err(BudgetExceeded),
  )
}
