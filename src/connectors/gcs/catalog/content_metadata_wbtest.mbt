///|
fn content_test_wire(extra? : String = "") -> String {
  "{\"bucket\":\"bucket\",\"name\":\"in/é%2F.csv\",\"generation\":\"9007199254740993\",\"metageneration\":\"9007199254740995\",\"size\":\"9\",\"contentType\":\"text/csv\",\"crc32c\":\"4waSgw==\"" +
  extra +
  "}"
}

///|
fn content_test_read(
  wire : String,
  maximum? : Int64 = 9L,
) -> Result[String, ContentMetadataIssue] {
  content_metadata_json(
    @utf8.encode(wire),
    "bucket",
    "in/é%2F.csv",
    "9007199254740993",
    maximum,
    {
      max_bytes: 4096,
      max_nodes: 4096,
      max_depth: 64,
      max_metadata_entries: 4096,
    },
  )
}

///|
test "GCS Content metadata retains exact original decimal and decomposed path DATA" {
  let projection = content_test_read(content_test_wire()).unwrap()
  guard @json.parse(projection) is Object(root) else {
    abort("private projection")
  }
  assert_eq(root.get("objectName"), Some("in/é%2F.csv".to_json()))
  assert_eq(root.get("generation"), Some("9007199254740993".to_json()))
  assert_eq(root.get("metageneration"), Some("9007199254740995".to_json()))
  assert_eq(root.get("sizeBytes"), Some("9".to_json()))
  assert_true(
    content_test_read(content_test_wire(), maximum=8L) is Err(MetadataMismatch),
  )
}

///|
test "GCS Content metadata rejects ambiguous and malformed original bytes" {
  for
    extra in [
      ",\"generation\":\"9007199254740993\"", ",\"gene\\u0072ation\":\"9007199254740993\"",
    ] {
    assert_true(
      content_test_read(content_test_wire(extra~)) is Err(InvalidMetadata),
    )
  }
  assert_true(
    content_test_read(content_test_wire() + "x") is Err(InvalidMetadata),
  )
  assert_true(
    content_metadata_json(b"\xff", "bucket", "in/x", "1", 9L, {
      max_bytes: 4096,
      max_nodes: 4096,
      max_depth: 64,
      max_metadata_entries: 4096,
    })
    is Err(InvalidMetadata),
  )
}

///|
test "GCS Content metadata representation and checksum refusals stay separate" {
  assert_true(
    content_test_read(content_test_wire(extra=",\"contentEncoding\":\"br\""))
    is Err(RepresentationUnsupported),
  )
  assert_true(
    content_test_read(content_test_wire(extra=",\"md5Hash\":\"bad\""))
    is Err(InvalidDigest),
  )
  assert_true(
    content_test_read(content_test_wire(extra=",\"md5Hash\":null"))
    is Err(InvalidDigest),
  )
  guard @json.parse(
      content_test_read(
        content_test_wire(extra=",\"contentEncoding\":\"gzip\""),
      ).unwrap(),
    )
    is Object(gzip) else {
    abort("private projection")
  }
  assert_eq(gzip.get("contentEncoding"), Some("gzip".to_json()))
}

///|
test "GCS Content metadata never aliases normalized paths or overflows provider sizes" {
  assert_true(
    content_metadata_json(
      @utf8.encode(content_test_wire()),
      "bucket",
      "in/é%2F.csv",
      "9007199254740993",
      9L,
      {
        max_bytes: 4096,
        max_nodes: 4096,
        max_depth: 64,
        max_metadata_entries: 4096,
      },
    )
    is Err(MetadataMismatch),
  )
  assert_false(content_decimal("01", positive=false))
  assert_false(content_decimal("0", positive=true))
  assert_true(content_decimal("18446744073709551615", positive=true))
  assert_false(content_decimal("184467440737095516150", positive=true))
}
