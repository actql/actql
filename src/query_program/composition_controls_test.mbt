///|
test "composition assertion and Effect retain the existing named Result owner" {
  let text = "FROM pair |> ASSERT UNIQUE BY (x) |> RESULT updates |> EFFECT save UPDATE TARGET 'connector://crm-main/Test_Record__c' MAPPING `mapping:fixture.v1` FROM RESULT updates ID x SET (Name = y)"
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(program)
  assert_true(body.contains("\"assert_rows\":{\"unique_by\":[\"x\"]}"))
  assert_true(
    body.contains(
      "\"effects\":{\"save\":{\"update\":{\"from\":{\"result\":\"rows\"},\"id\":\"x\",\"mapping\":\"mapping:fixture.v1\",\"set\":{\"Name\":{\"field\":\"y\"}},\"target\":\"connector://crm-main/Test_Record__c\"}}}",
    ),
  )
  assert_eq(@program.export_count(program), 1)
  assert_true(
    body.contains(
      "\"updates\":{\"from\":{\"result\":\"rows\",\"stage\":\"main\"}}",
    ),
  )
}

///|
test "Effect accepts existing literal values and refuses computed or foreign Result inputs" {
  let prefix = "FROM pair |> RESULT updates |> EFFECT save UPDATE TARGET 'connector://c/T' MAPPING m FROM RESULT "
  for
    tail in [
      "unknown ID x SET (Name = y)", "updates ID x SET (Name = y + 1)", "updates ID missing SET (Name = y)",
      "updates ID x SET (Name = y, Name = x)",
    ] {
    assert_true(
      compile(
        @query.parse_query(prefix + tail, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(_),
    )
  }
  let actual = compile(
    @query.parse_query(
      prefix + "updates ID x SET (Name = 'é\\r\\n')",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(actual).contains("\"literal\":\"é\\r\\n\""))
}

///|
test "unshared DATA retains its ordinary Source predicate exactly once" {
  let actual = compile_query_script(
    @query.parse_query_script(
      "DATA kept = FROM orders |> WHERE id = id |> SELECT id; FROM kept |> SELECT id",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), captured_stage: Some("capture"), },
    construction_limits(),
  ).unwrap()
  let body = semantic(actual)
  assert_true(
    body.contains("\"filter\":{\"eq\":[{\"field\":\"id\"},{\"field\":\"id\"}]}"),
  )
  assert_false(body.contains("\"filter\":{\"literal\":true}"))
  assert_eq(body.split("\"eq\"").length(), 2)
  assert_eq(@program.stage_count(actual), 2)
}

///|
test "DATA JOIN retains the authored output guard rather than the frontend default" {
  let text = "DATA joined = SELECT l.x AS x FROM pair AS l JOIN pair AS r ON l.x = r.x MAX_OUTPUT_ROWS 10; FROM joined |> RESULT updates"
  let script = @query.parse_query_script(text, syntax_limits()).unwrap()
  let actual = compile_query_script(
    script,
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(actual).contains("\"max_output_rows\":10"))
  assert_true(
    compile_query_script(script, pair_context(), {
      ..construction_limits(),
      max_join_output_rows: 9L,
    })
    is Err(_),
  )
}
