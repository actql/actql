///|
test "captured Pipe JOIN chain uses the existing shared source binding" {
  let text = "FROM records AS l |> JOIN (SELECT 3 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 |> WHERE r.k > 2 |> JOIN (SELECT 3 AS k) AS s ON r.k = s.k MAX_OUTPUT_ROWS 10 |> SELECT l.id AS id |> ORDER BY id"
  let formats : Array[Format] = [Text, Sql]
  for format in formats {
    let source = match format {
      Sql =>
        "SELECT id FROM records |> AS l" +
        text.strip_prefix("FROM records AS l").unwrap().to_owned()
      _ => text
    }
    let lowered = match lower(source, format, Some(test_context())) {
      Ok(value) => value
      Err(QueryLowering(@query.UnsupportedCte)) => fail("UnsupportedCte")
      Err(QueryLowering(@query.UnsupportedJoin)) => fail("UnsupportedJoin")
      Err(QueryLowering(@query.AmbiguousColumn)) => fail("AmbiguousColumn")
      Err(QueryLowering(@query.UnsupportedOrdering)) =>
        fail("UnsupportedOrdering")
      Err(QueryLowering(@query.Expression(_))) => fail("Expression")
      Err(QuerySyntax(_)) => fail("QuerySyntax")
      Err(_) => fail("other frontend issue")
    }
    assert_true(lowered.program is Some(_))
    assert_eq(lowered.document.split("\"connector\":").length() - 1, 1)
    assert_eq(lowered.document.split("\"join\":").length() - 1, 2)
    assert_eq(lowered.document.split("\"max_output_rows\":10").length() - 1, 2)
    assert_true(lowered.document.contains("\"gt\":[{\"field\":"))
    assert_true(lowered.document.contains("},{\"literal\":2}]"))
    assert_true(lowered.document.contains("\"fields\":[\"id\"]"))
  }
}
