///|
test "SQL and Pipe parse repeat reverse nested calls with ordinary expressions" {
  for
    source in [
      "SELECT REPEAT('😀é',2) AS value", "SELECT TRUE AS seed |> SELECT REVERSE('😀é') AS value",
      "SELECT REPEAT(@s,@n), REVERSE(@s)", "SELECT `REVERSE`(`REPEAT`('a',2)) AS value",
      "SELECT IF(FALSE,REPEAT('a',-1),'safe') AS value",
    ] {
    assert_true(parse_query(source, query_limits()) is Ok(_), msg=source)
  }
}
