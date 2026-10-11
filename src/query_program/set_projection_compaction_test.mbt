///|
test "implicit set projection composes alignment without another value evaluation" {
  // Positional append maps the right output to id. The existing derive runs
  // once; alignment changes only the following column projection.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":10}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_set_term_1"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_4"},{"from":"aql_script_seed_4","derive":{"aql_query_expr_0":{"literal":11}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_set_term_3"},{"from":"aql_data_set_term_1","append":{"with":"aql_data_set_term_3"},"as":"aql_data_0"},{"from":"aql_data_0","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile_with_set(
    "DATA e = SELECT 10 AS id UNION ALL SELECT 11 AS other; FROM e |> SELECT id",
  )
  assert_eq(semantic(actual), semantic(expected))
  for p in [expected, actual] {
    assert_true(
      @check.check_parsed(p, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "public parenthesized JOIN source fits the existing 32 task shape" {
  let left = "SELECT 2 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) UNION ALL SELECT 1 UNION ALL SELECT 2"
  let right = "SELECT 2 AS key,20 AS tag UNION ALL SELECT CAST(NULL AS FLOAT64),99 UNION ALL SELECT 2,21 UNION ALL SELECT 3,30"
  let p = row_on_query(
    "SELECT l.id,r.tag FROM (" +
    left +
    ") l JOIN (" +
    right +
    ") r ON (l.id)=((r.key)) MAX_OUTPUT_ROWS 10 ORDER BY tag,id",
  ).unwrap()
  assert_eq(@program.stage_count(p), 1)
  let body = @wire.open_object(@program.stage_body(@program.stages(p)[0])).unwrap()
  let steps = @wire.lookup(body, "steps").unwrap()
  assert_eq(@wire.array_length(steps), Some(32))
  let document = semantic(p)
  assert_true(!document.contains("aql_data_set_aligned_"))
  assert_true(document.contains("\"max_output_rows\":10"))
  assert_true(document.contains("\"fields\":[\"id\",\"tag\"]"))
}
