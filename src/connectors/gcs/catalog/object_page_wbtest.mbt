///|
fn object_page_wire(items : String, next? : String = "") -> String {
  "{\"kind\":\"storage#objects\",\"items\":" + items + next + "}"
}

///|
fn object_page_read(
  wire : String,
  maximum? : Int = 2,
) -> Result[ObjectMetadataPage, ObjectMetadataIssue] {
  admit_object_metadata_page(@utf8.encode(wire), "bucket", "in/", maximum, {
    max_bytes: 8192,
    max_nodes: 500,
    max_depth: 16,
    max_metadata_entries: 4,
  })
}

///|
test "GCS object Source projection is exact Decimal DATA and opaque JSON not exported value wire" {
  let wire = object_page_wire(
    "[" +
    metadata_wire(
      extra=",\"contentType\":\"text/csv\",\"storageClass\":\"COLDLINE\",\"updated\":\"2026-10-17T00:00:00Z\",\"md5Hash\":\"AAAAAA==\",\"crc32c\":\"crxyRA==\",\"metadata\":{\"actql-request\":\"private\",\"$json\":\"user\",\"é\":\"é\\r\\n%2F\"}",
    ).replace(old="\"size\":\"7\"", new="\"size\":\"9223372036854775807\"") +
    "]",
  )
  let page = object_page_read(wire).unwrap()
  let expected =
    #|{"content_type":"text/csv","crc32c":"crxyRA==","generation":"9007199254740993","md5":"AAAAAA==","metadata":{"$json":"user","é":"é\r\n%2F"},"metageneration":"2","name":"in/é%2F.csv","size":"9223372036854775807","storage_class":"COLDLINE","updated":"2026-10-17T00:00:00.000Z","version":"9007199254740993"}
  let maximum = @utf8.encode(expected).length()
  assert_eq(
    object_metadata_page_row_json(page, 0, maximum, metadata_limits()).unwrap(),
    expected,
  )
  assert_true(
    object_metadata_page_row_json(page, 0, maximum - 1, metadata_limits())
    is Err(BudgetExceeded),
  )
  assert_eq(
    object_metadata_page_response_sha256(page),
    @sha.hex(@utf8.encode(wire)),
  )
  assert_true(
    page.items[0].metadata.unwrap().contains(("actql-request", "private")),
  )
}

///|
test "GCS updated timestamp uses the same UTC instant without rounding provider precision" {
  for
    (reported, expected) in [
      ("2026-10-17T00:00:00Z", "2026-10-17T00:00:00.000Z"),
      ("2026-10-17T00:00:00.1Z", "2026-10-17T00:00:00.100Z"),
      ("2026-10-17T00:00:00.12Z", "2026-10-17T00:00:00.120Z"),
      ("2026-10-17T00:00:00.123Z", "2026-10-17T00:00:00.123Z"),
      ("2026-10-17T00:00:00.123000000Z", "2026-10-17T00:00:00.123Z"),
      ("2026-10-17T01:30:00+01:30", "2026-10-17T00:00:00.000Z"),
      ("2026-10-16T22:30:00-01:30", "2026-10-17T00:00:00.000Z"),
      ("2026-01-01T00:30:00+01:00", "2025-12-31T23:30:00.000Z"),
      ("2000-03-01T00:00:00+00:01", "2000-02-29T23:59:00.000Z"),
    ] {
    assert_eq(object_source_timestamp(reported), Some(expected))
    let wire = object_page_wire(
      "[" + metadata_wire(extra=",\"updated\":\"" + reported + "\"") + "]",
    )
    let page = object_page_read(wire).unwrap()
    assert_eq(page.items[0].updated, Some(reported))
    assert_eq(
      object_metadata_page_response_sha256(page),
      @sha.hex(@utf8.encode(wire)),
    )
    assert_true(
      object_metadata_page_row_json(page, 0, 8192, metadata_limits())
      .unwrap()
      .contains("\"updated\":\"" + expected + "\""),
    )
  }
  for
    invalid in [
      "2026-10-17T00:00:00.123001Z", "2026-10-17T00:00:00.000000001Z", "2026-10-17T00:00:00.Z",
      "2026-10-17T00:00:00.0000000000Z", "2026-02-29T00:00:00Z", "2026-10-17T00:00:60Z",
      "2026-10-17T00:00:00+24:00", "2026-10-17T00:00:00+01:60", "0000-01-01T00:00:00+00:01",
      "9999-12-31T23:59:59-00:01",
    ] {
    assert_eq(object_source_timestamp(invalid), None)
    let page = object_page_read(
      object_page_wire(
        "[" + metadata_wire(extra=",\"updated\":\"" + invalid + "\"") + "]",
      ),
    ).unwrap()
    assert_true(
      object_metadata_page_row_json(page, 0, 8192, metadata_limits())
      is Err(InvalidMetadata),
    )
    assert_eq(page.items[0].updated, Some(invalid))
  }
}

///|
test "GCS object Source distinguishes absent and empty metadata while rejecting null reports" {
  let missing = object_page_read(object_page_wire("[" + metadata_wire() + "]")).unwrap()
  let empty = object_page_read(
    object_page_wire("[" + metadata_wire(extra=",\"metadata\":{}") + "]"),
  ).unwrap()
  assert_true(
    object_metadata_page_row_json(missing, 0, 8192, metadata_limits())
    .unwrap()
    .contains("\"metadata\":null"),
  )
  assert_true(
    object_metadata_page_row_json(empty, 0, 8192, metadata_limits())
    .unwrap()
    .contains("\"metadata\":{}"),
  )
  for index in [-1, 1] {
    assert_true(
      object_metadata_page_row_json(missing, index, 8192, metadata_limits())
      is Err(InvalidMetadata),
    )
  }
  assert_true(
    object_metadata_page_row_json(empty, 0, 0, metadata_limits())
    is Err(InvalidLimits),
  )
  assert_true(
    object_metadata_page_row_json(empty, 0, 8192, {
      ..metadata_limits(),
      max_nodes: 1,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "GCS object Source prefix request narrows exact installed scope before physical I/O" {
  for request in [b"{}", b"{\"prefix\":null}"] {
    assert_eq(
      object_listing_prefix("in/é/", request, metadata_limits()).unwrap(),
      "in/é/",
    )
  }
  assert_eq(
    object_listing_prefix(
      "in/é/",
      @utf8.encode("{\"prefix\":\"in/é/%2F\"}"),
      metadata_limits(),
    ).unwrap(),
    "in/é/%2F",
  )
  for request in ["{\"prefix\":\"in/é/\"}", "{\"prefix\":\"outside/\"}"] {
    assert_true(
      object_listing_prefix("in/é/", @utf8.encode(request), metadata_limits())
      is Err(ObjectMismatch),
    )
  }
  for
    request in [
      b"[]", b"{\"prefix\":1}", b"{\"prefix\":\"in/\",\"prefix\":\"out/\"}", b"{\"glob\":\"*\"}",
      b"\xff",
    ] {
    assert_true(
      object_listing_prefix("in/", request, metadata_limits())
      is Err(InvalidMetadata),
    )
  }
  assert_true(
    object_listing_prefix("in/", b"{}", { ..metadata_limits(), max_bytes: 1, })
    is Err(BudgetExceeded),
  )
}

///|
test "GCS object page keeps exact Int64 and original physical digest" {
  let wire = object_page_wire(
    "[" +
    metadata_wire().replace(
      old="\"size\":\"7\"",
      new="\"size\":\"9223372036854775807\"",
    ) +
    "]",
  )
  let page = object_page_read(wire).unwrap()
  let row = object_metadata_page_at(page, 0).unwrap()
  assert_eq(row.generation, 9007199254740993L)
  assert_eq(row.metageneration, 2L)
  assert_eq(row.size, 9223372036854775807L)
  assert_eq(row.name, "in/é%2F.csv")
  assert_eq(
    object_metadata_page_response_sha256(page),
    @sha.hex(@utf8.encode(wire)),
  )
  assert_eq(object_metadata_page_count(page), 1)
  assert_eq(object_metadata_page_next_token(page), None)
  assert_true(object_metadata_page_at(page, -1) is None)
  assert_true(object_metadata_page_at(page, 1) is None)
}

///|
test "GCS empty object pages retain continuation and absence is not null" {
  assert_true(
    admit_object_metadata_page(
      b"{\"kind\":\"storage#objects\"}",
      "",
      "in/",
      0,
      metadata_limits(),
    )
    is Err(ObjectMismatch),
  )
  for wire in ["{\"kind\":\"storage#objects\"}", object_page_wire("[]")] {
    assert_eq(
      object_metadata_page_count(object_page_read(wire, maximum=0).unwrap()),
      0,
    )
  }
  let page = object_page_read(
    object_page_wire("[]", next=",\"nextPageToken\":\"é%2F\""),
  ).unwrap()
  assert_eq(object_metadata_page_count(page), 0)
  assert_eq(object_metadata_page_next_token(page), Some("é%2F"))
  for
    wire in [
      object_page_wire("null"),
      object_page_wire("{}"),
      object_page_wire("[]", next=",\"nextPageToken\":null"),
      object_page_wire("[]", next=",\"nextPageToken\":\"\""),
      object_page_wire("[]", next=",\"nextPageToken\":\"bad\\n\""),
    ] {
    assert_true(object_page_read(wire) is Err(InvalidMetadata))
  }
}

///|
test "GCS object pages refuse every foreign item before any page escapes" {
  let good = metadata_wire()
  for
    bad in [
      good.replace(old="\"bucket\":\"bucket\"", new="\"bucket\":\"foreign\""),
      good.replace(old="in/é%2F.csv", new="outside/file"),
      good.replace(old="\"9007199254740993\"", new="9007199254740992"),
      good.replace(old="\"9007199254740993\"", new="\"9223372036854775808\""),
      good.replace(old="\"size\":\"7\"", new="\"size\":\"-1\""),
      "{}",
    ] {
    assert_true(
      object_page_read(object_page_wire("[" + good + "," + bad + "]")) is Err(_),
    )
  }
}

///|
test "GCS object pages preserve missing metadata and exact private marker projection" {
  let raw = metadata_wire(
    extra=",\"metadata\":{\"actql-request\":\"private\",\"Actql-request\":\"user\",\"é\":\"é\\r\\n\"}",
  )
  let page = object_page_read(
    object_page_wire("[" + metadata_wire() + "," + raw + "]"),
  ).unwrap()
  assert_eq(object_metadata_page_at(page, 0).unwrap().metadata, None)
  let metadata = object_metadata_page_at(page, 1).unwrap().metadata.unwrap()
  assert_eq(metadata, [("Actql-request", "user"), ("é", "é\r\n")])
  metadata[0] = ("changed", "changed")
  assert_eq(object_metadata_page_at(page, 1).unwrap().metadata.unwrap(), [
    ("Actql-request", "user"),
    ("é", "é\r\n"),
  ])
  assert_true(
    page.items[1].metadata.unwrap().contains(("actql-request", "private")),
  )
  assert_true(
    object_page_read(
      object_page_wire("[" + metadata_wire(extra=",\"metadata\":null") + "]"),
    )
    is Err(InvalidMetadata),
  )
}

///|
test "GCS object page enforces whole-page and item limits before projection" {
  let wire = object_page_wire("[" + metadata_wire() + "]")
  let bytes = @utf8.encode(wire)
  let limits : ObjectMetadataLimits = {
    max_bytes: bytes.length(),
    max_nodes: 500,
    max_depth: 16,
    max_metadata_entries: 4,
  }
  assert_true(
    admit_object_metadata_page(bytes, "bucket", "in/", 1, limits) is Ok(_),
  )
  assert_true(
    admit_object_metadata_page(bytes, "bucket", "in/", 1, {
      ..limits,
      max_bytes: bytes.length() - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(object_page_read(wire, maximum=0) is Err(BudgetExceeded))
  assert_true(object_page_read(wire, maximum=-1) is Err(InvalidLimits))
  assert_true(
    admit_object_metadata_page(bytes, "bucket", "in/", 1, {
      ..limits,
      max_nodes: 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    admit_object_metadata_page(bytes, "bucket", "in/", 1, {
      ..limits,
      max_depth: 1,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "GCS object page rejects invalid UTF8 duplicate metadata and nonempty prefixes" {
  let good = object_page_wire("[" + metadata_wire() + "]")
  let duplicate = good.replace(
    old="\"size\":\"7\"",
    new="\"size\":\"7\",\"size\":\"8\"",
  )
  assert_true(object_page_read(duplicate) is Err(InvalidMetadata))
  assert_true(
    admit_object_metadata_page(b"\xff", "bucket", "in/", 1, metadata_limits())
    is Err(InvalidMetadata),
  )
  for
    suffix in [
      ",\"prefixes\":[\"in/sub/\"]", ",\"prefixes\":null", ",\"prefixes\":{}",
    ] {
    assert_true(
      object_page_read(object_page_wire("[]", next=suffix))
      is Err(InvalidMetadata),
    )
  }
  assert_true(
    object_page_read(object_page_wire("[]", next=",\"prefixes\":[]")) is Ok(_),
  )
}
