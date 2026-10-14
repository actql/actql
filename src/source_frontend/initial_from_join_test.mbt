///|
test "initial FROM JOIN and explicit Pipe JOIN share one captured Source" {
  let join = "JOIN (SELECT 3 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10"
  let forms : Array[(String, Format)] = [
    ("SELECT l.id AS id FROM records AS l " + join, Sql),
    ("FROM records AS l " + join + " |> SELECT l.id AS id", Text),
    ("FROM records AS l |> " + join + " |> SELECT l.id AS id", Text),
  ]
  for (source, format) in forms {
    let actual = lower(source, format, Some(registered_test_context())).unwrap()
    assert_true(actual.program is Some(_))
    assert_eq(actual.document.split("\"connector\":").length() - 1, 1)
    assert_eq(actual.document.split("\"join\":").length() - 1, 1)
    assert_true(actual.document.contains("\"max_output_rows\":10"))
    assert_true(actual.document.contains("\"fields\":[\"id\"]"))
  }
}
