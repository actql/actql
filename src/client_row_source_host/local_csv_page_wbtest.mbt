///|
fn fixture_local_csv_page(
  data : String,
  max_bytes? : Int = 256,
  max_field_bytes? : Int = 40,
  max_rows? : Int = 3,
  max_page_bytes? : Int = 1024,
) -> Result[String, LocalCsvPageIssue] {
  encode_local_csv_page(
    @utf8.encode(data),
    ["id", "name"],
    [true, false],
    ["id"],
    max_bytes,
    max_field_bytes,
    max_rows,
    max_page_bytes,
  )
}

///|
test "Local CSV yields original #3740 rows and exact canonical Int64 text" {
  assert_eq(
    fixture_local_csv_page("id,name\n1,A\n2,B\n3,C\n"),
    Ok(
      "[{\"id\":\"1\",\"name\":\"A\"},{\"id\":\"2\",\"name\":\"B\"},{\"id\":\"3\",\"name\":\"C\"}]",
    ),
  )
  assert_eq(
    fixture_local_csv_page(
      "\uFEFFname,id\r\n\"A, \"\"quoted\"\"\r\nline\",-9223372036854775808\r\n,9223372036854775807",
    ),
    Ok(
      "[{\"name\":\"A, \\\"quoted\\\"\\r\\nline\",\"id\":\"-9223372036854775808\"},{\"name\":\"\",\"id\":\"9223372036854775807\"}]",
    ),
  )
  assert_eq(fixture_local_csv_page("id,name\n"), Ok("[]"))
  assert_eq(
    fixture_local_csv_page("id,name\n1,"),
    Ok("[{\"id\":\"1\",\"name\":\"\"}]"),
  )
}

///|
test "Local CSV rejects bad width header quoting encoding and exact key values" {
  for
    pair in [
      ("id,id\n1,A", InvalidLocalCsvHeader),
      ("id,other\n1,A", InvalidLocalCsvHeader),
      ("id,name\n1,A,", InvalidLocalCsvWidth),
      ("id,name\n1", InvalidLocalCsvWidth),
      ("id,name\n1,\"A", InvalidLocalCsvQuote),
      ("id,name\n1,\"A\"x", InvalidLocalCsvSeparator),
      ("id,name\r1,A", InvalidLocalCsvSeparator),
      ("id,name\n1,\u0000", InvalidLocalCsvValue),
      ("id,name\n9223372036854775808,A", InvalidLocalCsvInt64),
      ("id,name\n-0,A", InvalidLocalCsvInt64),
      ("id,name\n01,A", InvalidLocalCsvInt64),
      ("id,name\n1,A\n1,B", DuplicateLocalCsvKey),
    ] {
    assert_eq(fixture_local_csv_page(pair.0), Err(pair.1))
  }
  assert_eq(
    encode_local_csv_page(
      b"id,name\n1,\xff",
      ["id", "name"],
      [true, false],
      ["id"],
      256,
      40,
      3,
      1024,
    ),
    Err(InvalidLocalCsvEncoding),
  )
}

///|
test "Local CSV uses independent exact raw record and JSON output limits" {
  let data = "id,name\n1,ABCD"
  assert_true(
    fixture_local_csv_page(
      data,
      max_bytes=data.length(),
      max_field_bytes=4,
      max_rows=1,
    )
    is Ok(_),
  )
  assert_eq(
    fixture_local_csv_page(data, max_bytes=data.length() - 1),
    Err(LocalCsvBytesLimit),
  )
  assert_eq(
    fixture_local_csv_page(data + "E", max_field_bytes=4),
    Err(LocalCsvFieldLimit),
  )
  assert_eq(
    fixture_local_csv_page(data + "\n2,E", max_rows=1),
    Err(LocalCsvRowsLimit),
  )
  let escaped = "id,name\n1,😀\n2,\t"
  let wire = "[{\"id\":\"1\",\"name\":\"😀\"},{\"id\":\"2\",\"name\":\"\\t\"}]"
  let extent = @utf8.encode(wire).length()
  assert_eq(fixture_local_csv_page(escaped, max_page_bytes=extent), Ok(wire))
  assert_eq(
    fixture_local_csv_page(escaped, max_page_bytes=extent - 1),
    Err(LocalFilesPageBytesLimit),
  )
}
