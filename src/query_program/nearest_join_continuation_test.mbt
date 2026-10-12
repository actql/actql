///|
fn nearest_join_checked(text : String) -> @program.Program raise {
  let actual = match with_carrier_program(text, nearest_context()) {
    Err(UnknownRelation) => fail("JOIN tail candidate: UnknownRelation")
    other => with_demand_program(other)
  }
  nearest_member_require_checked(actual)
  actual
}

///|
test "JOIN tail resolves the shared Relation NEAREST candidate once" {
  let actual = nearest_join_checked(
    "WITH qs AS (FROM queries) FROM qs AS q |> JOIN candidates AS gate ON q.request_id = gate.item_id MAX_OUTPUT_ROWS 4 |> NEAREST candidates AS c QUERY KEY (q.request_id) VECTOR q.embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 AS hit |> SELECT hit.rank AS rank |> ORDER BY rank",
  )
  let body = semantic(actual)
  // gate and c refer to one installed candidate seed, with distinct roles.
  // The original inputs have no matching JOIN key, so the public oracle is
  // empty; discarding the authored JOIN would instead produce two matches.
  assert_eq(body.split("\"values\":{").length(), 3)
  assert_eq(body.split("\"nearest\":{").length(), 2)
  assert_eq(body.split("\"to_vectors\":{").length(), 3)
  assert_eq(body.split("\"join\":{").length(), 2)
  assert_true(body.contains("\"kind\":\"inner\""))
}

///|
test "JOIN tail preserves qualified query roles and intrinsic Vectors candidate roles" {
  let actual = nearest_join_checked(
    "WITH cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) FROM queries AS q |> JOIN candidates AS gate ON q.request_id = gate.item_id MAX_OUTPUT_ROWS 4 |> WHERE q.note IS NULL |> LIMIT 1 |> NEAREST cv AS c QUERY KEY (q.request_id) VECTOR q.embedding METRIC dot K 2 AS hit |> SELECT hit.rank AS rank |> ORDER BY rank",
  )
  let body = semantic(actual)
  assert_eq(body.split("\"values\":{").length(), 3)
  assert_eq(body.split("\"nearest\":{").length(), 2)
  assert_eq(body.split("\"to_vectors\":{").length(), 3)
  assert_eq(body.split("\"join\":{").length(), 2)
  assert_true(body.contains("\"is_null\":{\"field\":\"aql_chain_column_"))
  assert_true(body.contains("\"take\":{\"count\":1,\"offset\":0}"))
  assert_true(!body.contains("\"vectors\":true"))
}

///|
test "SELECT before JOIN-tail NEAREST uses evaluated output roles" {
  let actual = nearest_join_checked(
    "WITH cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) FROM queries AS q |> JOIN candidates AS gate ON q.request_id = gate.item_id MAX_OUTPUT_ROWS 4 |> SELECT q.request_id AS qid, q.embedding AS v |> NEAREST cv AS c QUERY KEY (qid) VECTOR v METRIC dot K 2 AS hit |> SELECT hit.rank AS rank |> ORDER BY rank",
  )
  let body = semantic(actual)
  assert_eq(body.split("\"values\":{").length(), 3)
  assert_eq(body.split("\"nearest\":{").length(), 2)
  assert_eq(body.split("\"to_vectors\":{").length(), 3)
  assert_eq(body.split("\"join\":{").length(), 2)
  assert_true(body.contains("\"query_key\":{\"object\":{\"qid\":{\"field\":"))
}
