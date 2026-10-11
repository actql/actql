///|
// Exact current public caller inputs, copied from independent authored fixtures.
// These cases execute the real parser and preserve outer binding boundaries.
// Host I/O, checker refusal, Provider execution and Result publication are separate.

///|
test "WITH current public caller acquired-data-null-duplicates-column-order" {
  let script = parse_query_script(
    "WITH copied AS (FROM records |> SELECT amount, id) FROM copied |> ORDER BY id |> RESULT copied_rows",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller acquired-data-shared-source-keeps-complete-input" {
  let script = parse_query_script(
    "WITH selected AS (FROM records |> WHERE amount >= 20 |> SELECT id), complete AS (FROM records |> SELECT amount, id) FROM complete |> ORDER BY id |> RESULT all_rows",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 2)
}

///|
test "WITH current public caller acquired-data-set-reuses-capture" {
  let script = parse_query_script(
    "WITH kept AS (FROM records |> WHERE id = 1 |> SELECT amount, id), combined AS (FROM kept |> SELECT amount, id |> UNION ALL (FROM records |> WHERE amount >= 20 |> SELECT amount, id)) FROM combined |> ORDER BY id |> RESULT all_rows",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 2)
}

///|
test "WITH current public caller acquired-data-empty-retains-schema" {
  let script = parse_query_script(
    "WITH copied AS (FROM records |> SELECT amount, id) FROM copied |> ORDER BY id |> RESULT copied_rows",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller acquired-data-parameter-declaration" {
  let script = parse_query_script(
    "WITH copied AS (FROM records |> WHERE amount >= @minimum |> SELECT amount, id) FROM copied |> ORDER BY id |> RESULT copied_rows",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller acquired-data-cte-pipe-body" {
  let script = parse_query_script(
    "WITH copied AS (WITH chosen AS (FROM records |> WHERE amount >= 20 |> SELECT amount, id) FROM `CHOSEN` |> SELECT amount, id) FROM copied |> ORDER BY id |> RESULT copied_rows",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller acquired-data-cte-set-shared-producer" {
  let script = parse_query_script(
    "WITH copied AS (WITH chosen AS (FROM records |> SELECT amount, id) SELECT amount, id FROM chosen UNION ALL SELECT amount, id FROM chosen) FROM copied |> ORDER BY id |> RESULT copied_rows",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller acquired-data-cte-shadows-outer-source" {
  let script = parse_query_script(
    "WITH copied AS (WITH records AS (SELECT amount, id FROM records WHERE id <= 2) SELECT amount, id FROM records) FROM copied |> ORDER BY id |> RESULT copied_rows",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller acquired-data-join-keeps-multiplicity-and-one-capture" {
  let script = parse_query_script(
    "WITH seed AS (FROM records |> SELECT amount, id), paired AS (SELECT l.amount, l.id FROM seed AS l JOIN seed AS r ON l.id = r.id) FROM paired |> ORDER BY id |> RESULT copied_rows",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 2)
}

///|
test "WITH current public caller acquired-data-cte-join-output-alias-order" {
  let script = parse_query_script(
    "WITH paired AS (WITH seed AS (FROM records |> SELECT amount, id) SELECT l.id AS amount, l.amount AS id FROM seed AS l JOIN seed AS r ON l.id = r.id ORDER BY amount + 1) FROM paired |> RESULT copied_rows",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller acquired-data-later-unregistered-source" {
  let script = parse_query_script(
    "WITH copied AS (FROM records |> SELECT id), missing AS (FROM unregistered |> SELECT id) FROM copied |> SELECT id",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 2)
}

///|
test "WITH current public caller acquired-data-removed-field" {
  let script = parse_query_script(
    "WITH copied AS (FROM records |> SELECT id) FROM copied |> SELECT amount",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller acquired-data-undeclared-parameter" {
  let script = parse_query_script(
    "WITH copied AS (FROM records |> WHERE amount >= @minimum |> SELECT id) FROM copied |> SELECT id",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller acquired-data-parameter-type-mismatch" {
  let script = parse_query_script(
    "WITH copied AS (FROM records |> WHERE amount >= @minimum |> SELECT id) FROM copied |> SELECT id",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller acquired-data-cte-scope-does-not-leak" {
  let script = parse_query_script(
    "WITH copied AS (WITH chosen AS (FROM records |> SELECT id) FROM chosen |> SELECT id) FROM chosen |> SELECT id",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller acquired-data-join-ambiguous-output" {
  let script = parse_query_script(
    "WITH seed AS (FROM records |> SELECT id), paired AS (SELECT id FROM seed AS l JOIN seed AS r ON l.id = r.id) FROM paired |> SELECT id",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 2)
}

///|
test "WITH current public caller python-client-public.py" {
  let script = parse_query_script(
    "WITH seed AS (SELECT 1 AS n) FROM seed |> EXTEND n + 1 AS value |> SELECT value |> RESULT answer",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller python_local_run_inputs.py" {
  let script = parse_query_script(
    "WITH seed AS (SELECT 1 AS n) FROM seed |> EXTEND n + 1 AS value |> SELECT value |> RESULT answer",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH current public caller composed-infer-effect.aql.template" {
  let script = parse_query_script(
    "WITH left_rows AS (FROM left_records |> WHERE id = id),\n     right_rows AS (FROM right_records |> WHERE id = id),\n     joined AS (SELECT l.id AS id, l.amount AS left_amount, r.amount AS right_amount\n  FROM left_rows AS l JOIN right_rows AS r ON l.id = r.id MAX_OUTPUT_ROWS 10)\nFROM joined\n  |> ASSERT UNIQUE BY (id)\n  |> INFER `model-task:composition-risk.v1` ITEM KEY (id)\n     INPUT (score = right_amount) KEEP (id, left_amount, right_amount) AS assessment\n  |> WHERE assessment.outcome = 'ok'\n  |> SELECT id, left_amount, right_amount, assessment.value.risk AS risk\n  |> ORDER BY id\n  |> RESULT classified\n  |> WHERE risk = 'high'\n  |> EXTEND 'a00000000000002' AS target_id, 'review-required' AS next_name\n  |> RESULT updates\n  |> EFFECT save UPDATE TARGET 'connector://crm-main/Test_Record__c'\n     MAPPING `__PUBLICATION_MAPPING_REF__`\n     FROM RESULT updates ID target_id SET (Name = next_name)\n",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 3)
}

///|
test "WITH current public caller composed-infer-effect-null-assert.aql.template" {
  let script = parse_query_script(
    "WITH left_rows AS (FROM left_records |> WHERE id = id),\n     right_rows AS (FROM right_records |> WHERE id = id),\n     joined AS (SELECT l.id AS id, l.amount AS left_amount, r.amount AS right_amount\n  FROM left_rows AS l JOIN right_rows AS r ON l.id = r.id MAX_OUTPUT_ROWS 10)\nFROM joined\n  |> ASSERT UNIQUE BY (right_amount)\n  |> ASSERT UNIQUE BY (id)\n  |> INFER `model-task:composition-risk.v1` ITEM KEY (id)\n     INPUT (score = right_amount) KEEP (id, left_amount, right_amount) AS assessment\n  |> WHERE assessment.outcome = 'ok'\n  |> SELECT id, left_amount, right_amount, assessment.value.risk AS risk\n  |> ORDER BY id\n  |> RESULT classified\n  |> WHERE risk = 'high'\n  |> EXTEND 'a00000000000002' AS target_id, 'review-required' AS next_name\n  |> RESULT updates\n  |> EFFECT save UPDATE TARGET 'connector://crm-main/Test_Record__c'\n     MAPPING `__PUBLICATION_MAPPING_REF__`\n     FROM RESULT updates ID target_id SET (Name = next_name)\n",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 3)
}
