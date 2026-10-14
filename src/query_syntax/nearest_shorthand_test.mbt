///|
test "short NEAREST accepts USING and defaults to exact cosine" {
  let query = parse_query(
    "FROM questions |> NEAREST corpus USING (query_vec) K 3 AS hit",
    query_limits(),
    source_path="rag.aql",
  ).unwrap()
  guard operation_at(query, 0) is Some(Nearest(clause)) else {
    fail("NEAREST clause")
  }
  assert_eq(clause.metric, "cosine")
  assert_eq(clause.k, 3L)
  assert_eq(clause.relation.map(part => part.value), ["corpus"])
  assert_eq(clause.name.value, "hit")
  assert_true(clause.keep.is_empty())
}
