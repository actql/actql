///|
test "composition controls preserve explicit assertion bound and terminal Effect" {
  let text = "DATA l = FROM left_records |> WHERE id = id; DATA r = FROM right_records |> WHERE id = id; DATA joined = SELECT l.id AS id, r.amount AS score FROM l JOIN r ON l.id = r.id MAX_OUTPUT_ROWS 10; FROM joined |> ASSERT UNIQUE BY (id) |> RESULT updates |> EFFECT save UPDATE TARGET 'connector://crm-main/Test_Record__c' MAPPING `mapping:fixture.v1` FROM RESULT updates ID id SET (Name = score)"
  assert_true(parse_query_script(text, query_limits()) is Ok(_))
}

///|
test "Effect is terminal and declaration bodies cannot publish it" {
  for
    text in [
      "FROM t |> RESULT rows |> EFFECT save UPDATE TARGET 'connector://c/T' MAPPING m FROM RESULT rows ID id SET (Name = name) |> WHERE id = 1",
      "DATA x = FROM t |> EFFECT save UPDATE TARGET 'connector://c/T' MAPPING m FROM RESULT rows ID id SET (Name = name); FROM x",
      "FROM t |> ASSERT UNIQUE BY ()", "FROM l JOIN r ON l.id = r.id MAX_OUTPUT_ROWS 0 |> SELECT l.id",
      "FROM l JOIN r ON l.id = r.id MAX_OUTPUT_ROWS 9007199254740992 |> SELECT l.id",
    ] {
    assert_true(parse_query_script(text, query_limits()) is Err(_))
  }
}
