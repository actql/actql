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
  assert_eq(clause.candidate_alias.value, "corpus")
  let vector = clause.query_vector.unwrap()
  guard expression_node(vector, expression_root(vector)).unwrap().kind
    is Parenthesized(child) else {
    fail("authored wrapper")
  }
  guard expression_node(vector, child).unwrap().kind is Reference(path) else {
    fail("query vector reference")
  }
  assert_eq(path[0].value, "query_vec")
  assert_eq(clause.k, 3L)
  assert_eq(clause.relation.map(part => part.value), ["corpus"])
  assert_eq(clause.name.value, "hit")
  assert_true(clause.keep.is_empty())
}

///|
test "short NEAREST preserves explicit metric KEEP and candidate scope" {
  let query = parse_query(
    "FROM q |> NEAREST catalog.items AS c USING embedding METRIC l2 K 2 KEEP (q.*, c.body) AS hit",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 0) is Some(Nearest(clause)) else { fail("nearest") }
  assert_eq(clause.metric, "l2")
  assert_eq(clause.candidate_alias.value, "c")
  assert_eq(clause.keep.length(), 2)
  assert_true(clause.keep[0].wildcard)
  assert_eq(clause.keep[1].path.map(part => part.value), ["c", "body"])
}

///|
test "short NEAREST refuses two authored query vectors and malformed USING" {
  for
    tail in [
      "USING embedding QUERY KEY (id) VECTOR other K 1 AS hit", "USING K 1 AS hit",
      "USING (embedding K 1 AS hit", "USING embedding METRIC approximate K 1 AS hit",
      "USING embedding K 0 AS hit", "USING embedding K 1 KEEP () AS hit",
    ] {
    guard parse_query(
        "FROM q |> NEAREST corpus " + tail,
        query_limits(),
        source_path="short.aql",
      )
      is Err({ span: Some(span), .. }) else {
      fail(tail)
    }
    assert_eq(span.source_path, "short.aql")
  }
}
