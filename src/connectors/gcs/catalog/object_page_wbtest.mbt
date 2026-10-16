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
