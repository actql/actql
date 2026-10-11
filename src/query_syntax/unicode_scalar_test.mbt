///|
test "SQL and Pipe admit nested Unicode scalar calls with ordinary arguments" {
  for
    source in [
      "SELECT BYTE_LENGTH('😀') AS bytes", "SELECT TRUE AS seed |> SELECT OCTET_LENGTH('é') AS bytes",
      "SELECT UNICODE(@s), CHR(@n)", "SELECT `OCTET_LENGTH`(CHR(128512)) AS bytes",
      "SELECT IF(FALSE, CHR(-1), CHR(0)) AS value",
    ] {
    assert_true(parse_query(source, query_limits()) is Ok(_), msg=source)
  }
}
