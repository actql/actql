///|
test "SQL and Pipe admit nested ordinary SPLIT calls" {
  for
    source in [
      "SELECT SPLIT('a,b') AS parts", "SELECT TRUE AS seed |> SELECT SPLIT('a,b', LOWER(',')) AS parts",
      "SELECT SPLIT(s,@d) AS parts FROM input", "SELECT IF(TRUE, SPLIT('a'), SPLIT('b','')) AS parts",
    ] {
    assert_true(parse_query(source, query_limits()) is Ok(_), msg=source)
  }
}
