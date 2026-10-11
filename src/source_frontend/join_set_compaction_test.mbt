///|
test "public SQL and text routes preserve compact evaluated set JOIN inputs" {
  let source = "SELECT l.id,r.tag FROM (SELECT 2 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) UNION ALL SELECT 1 UNION ALL SELECT 2) l JOIN (SELECT 2 AS key,20 AS tag UNION ALL SELECT CAST(NULL AS FLOAT64),99 UNION ALL SELECT 2,21 UNION ALL SELECT 3,30) r ON (l.id)=((r.key)) MAX_OUTPUT_ROWS 10 ORDER BY tag,id"
  let context = bind_query_context([], "fixture.environment").unwrap()
  let formats : Array[Format] = [Sql, Text]
  for format in formats {
    let lowered = lower(source, format, Some(context)).unwrap()
    let program = lowered.program.unwrap()
    assert_eq(@program.stage_count(program), 1)
    let body = @wire.open_object(
      @program.stage_body(@program.stages(program)[0]),
    ).unwrap()
    let steps = @wire.lookup(body, "steps").unwrap()
    assert_eq(@wire.array_length(steps), Some(32), msg=lowered.document)
    assert_true(lowered.document.contains("\"max_output_rows\":10"))
    assert_true(lowered.document.contains("\"fields\":[\"id\",\"tag\"]"))
  }
}
