///|
fn metadata_limits() -> ObjectMetadataLimits {
  { max_bytes: 8192, max_nodes: 100, max_depth: 8, max_metadata_entries: 4, }
}

///|
fn metadata_wire(extra? : String = "") -> String {
  "{\"bucket\":\"bucket\",\"name\":\"in/é%2F.csv\",\"generation\":\"9007199254740993\",\"metageneration\":\"2\",\"size\":\"7\"" +
  extra +
  "}"
}

///|
fn metadata_read(wire : String) -> Result[ObjectMetadata, ObjectMetadataIssue] {
  admit_object_metadata(
    @utf8.encode(wire),
    "bucket",
    "in/",
    None,
    metadata_limits(),
  )
}

///|
test "GCS keeps exact generation integers and decomposed object names" {
  let value = metadata_read(metadata_wire()).unwrap()
  let fields = object_metadata_fields(value)
  assert_eq(fields.generation, 9007199254740993L)
  assert_eq(fields.metageneration, 2L)
  assert_eq(fields.size, 7L)
  assert_eq(fields.name, "in/é%2F.csv")
  assert_eq(object_metadata_version(value), "9007199254740993")
  assert_eq(fields.metadata, None)
  assert_eq(fields.content_type, None)
}

///|
test "GCS opaque custom metadata preserves NFD CR LF empty and percent text" {
  let value = metadata_read(
    metadata_wire(
      extra=",\"metadata\":{\"é\":\"é\\r\\n%2F\",\"empty\":\"\",\"\":\"empty key\"}",
    ),
  ).unwrap()
  let entries = object_metadata_fields(value).metadata.unwrap()
  assert_eq(entries, [("é", "é\r\n%2F"), ("empty", ""), ("", "empty key")])
  entries[0] = ("changed", "changed")
  assert_eq(object_metadata_fields(value).metadata.unwrap(), [
    ("é", "é\r\n%2F"),
    ("empty", ""),
    ("", "empty key"),
  ])
}

///|
test "GCS empty metadata is present and explicit null is not absent" {
  assert_eq(
    object_metadata_fields(
      metadata_read(metadata_wire(extra=",\"metadata\":{}")).unwrap(),
    ).metadata,
    Some([]),
  )
  assert_true(
    metadata_read(metadata_wire(extra=",\"metadata\":null"))
    is Err(InvalidMetadata),
  )
  assert_true(
    metadata_read(metadata_wire(extra=",\"contentType\":null"))
    is Err(InvalidMetadata),
  )
  assert_true(
    metadata_read(metadata_wire(extra=",\"metadata\":{\"key\":null}"))
    is Err(InvalidMetadata),
  )
}

///|
test "GCS all optional provider fields survive the metadata projection" {
  let value = metadata_read(
    metadata_wire(
      extra=",\"contentType\":\"text/csv\",\"contentEncoding\":\"gzip\",\"storageClass\":\"COLDLINE\",\"updated\":\"2026-10-16T00:00:00Z\",\"crc32c\":\"AAAAAA==\",\"md5Hash\":\"1B2M2Y8AsgTpgAmY7PhCfg==\"",
    ),
  ).unwrap()
  let fields = object_metadata_fields(value)
  assert_eq(fields.content_type, Some("text/csv"))
  assert_eq(fields.content_encoding, Some("gzip"))
  assert_eq(fields.storage_class, Some("COLDLINE"))
  assert_eq(fields.updated, Some("2026-10-16T00:00:00Z"))
  assert_eq(fields.crc32c, Some("AAAAAA=="))
  assert_eq(fields.md5, Some("1B2M2Y8AsgTpgAmY7PhCfg=="))
}

///|
test "GCS rejects numeric rounded overflow negative and noncanonical version text" {
  for
    integer in [
      "9007199254740993", "null", "\"01\"", "\"0\"", "\"-1\"", "\"9223372036854775808\"",
    ] {
    let wire = "{\"bucket\":\"bucket\",\"name\":\"in/file\",\"generation\":" +
      integer +
      ",\"metageneration\":\"2\",\"size\":\"7\"}"
    assert_true(metadata_read(wire) is Err(InvalidMetadata))
  }
  let maximum = "{\"bucket\":\"bucket\",\"name\":\"in/file\",\"generation\":\"9223372036854775807\",\"metageneration\":\"1\",\"size\":\"0\"}"
  assert_eq(
    object_metadata_fields(metadata_read(maximum).unwrap()).generation,
    9223372036854775807L,
  )
}

///|
test "GCS metadata cannot substitute bucket prefix or exact object identity" {
  let bytes = @utf8.encode(metadata_wire())
  for
    (bucket, prefix, name) in [
      ("foreign", "in/", None),
      ("bucket", "foreign/", None),
      ("bucket", "in/", Some("in/é%2F.csv")),
    ] {
    assert_true(
      admit_object_metadata(bytes, bucket, prefix, name, metadata_limits())
      is Err(ObjectMismatch),
    )
  }
  assert_true(
    admit_object_metadata(
      bytes,
      "bucket",
      "in/",
      Some("in/é%2F.csv"),
      metadata_limits(),
    )
    is Ok(_),
  )
}

///|
test "GCS metadata rejects duplicate keys truncated wire and invalid UTF8" {
  assert_true(
    metadata_read(metadata_wire(extra=",\"generation\":\"4\""))
    is Err(InvalidMetadata),
  )
  assert_true(
    metadata_read(
      metadata_wire(extra=",\"metadata\":{\"x\":\"a\",\"x\":\"b\"}"),
    )
    is Err(InvalidMetadata),
  )
  assert_true(metadata_read("{") is Err(InvalidMetadata))
  assert_true(
    admit_object_metadata(b"\xff", "bucket", "", None, metadata_limits())
    is Err(InvalidMetadata),
  )
}

///|
test "GCS metadata enforces exact wire and custom entry ceilings" {
  let bytes = @utf8.encode(
    metadata_wire(extra=",\"metadata\":{\"x\":\"a\",\"y\":\"b\"}"),
  )
  let limits = {
    ..metadata_limits(),
    max_bytes: bytes.length(),
    max_metadata_entries: 2,
  }
  assert_true(
    admit_object_metadata(bytes, "bucket", "in/", None, limits) is Ok(_),
  )
  assert_true(
    admit_object_metadata(bytes, "bucket", "in/", None, {
      ..limits,
      max_bytes: bytes.length() - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    admit_object_metadata(bytes, "bucket", "in/", None, {
      ..limits,
      max_metadata_entries: 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    admit_object_metadata(bytes, "bucket", "in/", None, {
      ..limits,
      max_nodes: 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    admit_object_metadata(bytes, "bucket", "in/", None, {
      ..limits,
      max_depth: 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    admit_object_metadata(bytes, "bucket", "in/", None, {
      ..limits,
      max_metadata_entries: -1,
    })
    is Err(InvalidLimits),
  )
}

///|
test "GCS original response digest is byte exact rather than a row identity" {
  let wire = metadata_wire()
  let first = metadata_read(wire).unwrap()
  let second = metadata_read(wire + "\n").unwrap()
  assert_eq(object_metadata_version(first), object_metadata_version(second))
  assert_not_eq(
    object_metadata_response_sha256(first),
    object_metadata_response_sha256(second),
  )
  assert_eq(
    object_metadata_response_sha256(first),
    @sha.hex(@utf8.encode(wire)),
  )
}
