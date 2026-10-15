// Literal controls from the original authored temporal fixture, not compiler output.

///|
test "original temporal public SELECT alias retains reserved AT refusal" {
  let source = "WITH l AS (SELECT 1 AS id, 10 AS at UNION ALL SELECT 2, 30 UNION ALL SELECT 3, 50), r AS (SELECT 7 AS id, 5 AS begin, 15 AS finish UNION ALL SELECT 8, 20, 25), matched AS (FROM l AS current |> asof_join(with: r, kind: 'left', by: [], left_id: current.id, left_time: current.at, right_time: r.begin, direction: 'backward', tolerance: 12, select: {id: left.id, value: right.id})) SELECT id, value FROM matched ORDER BY id"
  guard parse_query(source, { ..query_limits(), max_syntax_nodes: 1000, }, source_path="temporal.sql")
    is Err({ issue: Syntax("Reserved identifier requires backticks"), span: Some(span), }) else {
    fail("original reserved alias must remain refused")
  }
  assert_eq(span.source_path, "temporal.sql")
  assert_eq(span.start_byte, 33)
  assert_eq(span.end_byte, 33)
}

///|
test "quoting AT alone retains reserved CURRENT range alias refusal" {
  let source = "WITH l AS (SELECT 1 AS id, 10 AS `at` UNION ALL SELECT 2, 30 UNION ALL SELECT 3, 50), r AS (SELECT 7 AS id, 5 AS begin, 15 AS finish UNION ALL SELECT 8, 20, 25), matched AS (FROM l AS current |> asof_join(with: r, kind: 'left', by: [], left_id: current.id, left_time: current.at, right_time: r.begin, direction: 'backward', tolerance: 12, select: {id: left.id, value: right.id})) SELECT id, value FROM matched ORDER BY id"
  guard parse_query(source, { ..query_limits(), max_syntax_nodes: 1000, }, source_path="temporal.sql")
    is Err({ issue: Syntax("Reserved identifier requires backticks"), span: Some(span), }) else {
    fail("original reserved alias must remain refused")
  }
  assert_eq(span.source_path, "temporal.sql")
  assert_eq(span.start_byte, 184)
  assert_eq(span.end_byte, 184)
}

///|
test "temporal public text quotes only ordinary AT CURRENT aliases" {
  let source = "WITH l AS (SELECT 1 AS id, 10 AS `at` UNION ALL SELECT 2, 30 UNION ALL SELECT 3, 50), r AS (SELECT 7 AS id, 5 AS begin, 15 AS finish UNION ALL SELECT 8, 20, 25), matched AS (FROM l AS `current` |> asof_join(with: r, kind: 'left', by: [], left_id: current.id, left_time: current.at, right_time: r.begin, direction: 'backward', tolerance: 12, select: {id: left.id, value: right.id})) SELECT id, value FROM matched ORDER BY id"
  assert_true(parse_query(source, { ..query_limits(), max_syntax_nodes: 1000, }) is Ok(_))
}
