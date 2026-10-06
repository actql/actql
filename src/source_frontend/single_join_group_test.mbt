///|
test "single JOIN GROUP public input retains one captured shared source" {
  let formats : Array[Format] = [Sql, Text]
  for format in formats {
    let lowered = lower(
      "SELECT l.id, COUNT(*) AS n FROM records AS l JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 20 WHERE l.id > 0 GROUP BY l.id HAVING n > 1 ORDER BY id",
      format,
      Some(test_context()),
    ).unwrap()
    guard lowered.program is Some(program) else {
      fail("the public source route must produce an ordinary Program")
    }
    assert_eq(@program.stage_count(program), 2)
    assert_eq(lowered.document.split("\"connector\":").length() - 1, 1)
    assert_true(lowered.document.contains("\"max_output_rows\":20"))
    assert_true(lowered.document.contains("\"with\":\"source\""))
    assert_true(lowered.document.contains("\"filter\":{\"literal\":true}"))
    assert_true(lowered.document.contains("\"fields\":[\"id\",\"n\"]"))
  }
}

///|
test "single JOIN GROUP public input preserves raw source with derived right input" {
  let lowered = lower(
    "SELECT COUNT(*) AS n FROM records CROSS JOIN (SELECT 1 AS k) AS s MAX_OUTPUT_ROWS 10 WHERE records.id > 0 HAVING COUNT(*) > 1",
    Sql,
    Some(test_context()),
  ).unwrap()
  assert_true(lowered.program is Some(_))
  assert_true(lowered.document.contains("\"max_output_rows\":10"))
  assert_true(lowered.document.contains("\"fields\":[\"n\"]"))
}
