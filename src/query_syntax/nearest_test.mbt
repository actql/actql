///|
test "NEAREST parses two explicit key and vector roles and optional KEEP" {
  let query = parse_query(
    "FROM requests AS q |> NEAREST `catalog`.`items` AS c QUERY KEY (q.tenant, q.id) VECTOR q.embedding CANDIDATE KEY (c.tenant, c.id) VECTOR c.embedding METRIC COSINE K 2 KEEP (q.id AS request, c.*, *) AS neighbor",
    query_limits(),
  ).unwrap()
  match operation_at(query, 0) {
    Some(Nearest(clause)) => {
      assert_eq(clause.relation.map(part => part.value), ["catalog", "items"])
      assert_true(clause.relation[0].quoted)
      assert_eq(clause.query_keys.length(), 2)
      assert_eq(clause.candidate_keys[1].map(part => part.value), ["c", "id"])
      assert_eq(clause.metric, "cosine")
      assert_eq(clause.k, 2L)
      assert_eq(clause.keep.length(), 3)
      assert_eq(clause.keep[0].name.unwrap().value, "request")
      assert_true(clause.keep[1].wildcard)
      clause.query_keys.clear()
      clause.keep.clear()
      guard operation_at(query, 0) is Some(Nearest(fresh)) else {
        fail("nearest")
      }
      assert_eq(fresh.query_keys.length(), 2)
      assert_eq(fresh.keep.length(), 3)
    }
    _ => fail("NEAREST has its own typed clause")
  }
  let omitted = parse_query(
    "FROM requests |> NEAREST items AS c QUERY KEY (id) VECTOR embedding CANDIDATE KEY (c.id) VECTOR c.embedding METRIC dot K 1 AS neighbor",
    query_limits(),
  ).unwrap()
  guard operation_at(omitted, 0) is Some(Nearest(clause)) else {
    fail("nearest")
  }
  assert_true(clause.keep.is_empty())
}

///|
test "NEAREST rejects malformed clauses and preserves source diagnostics and bounds" {
  let prefix = "FROM q |> NEAREST c AS candidates "
  let roles = "QUERY KEY (id) VECTOR embedding CANDIDATE KEY (candidates.id) VECTOR candidates.embedding "
  for
    suffix in [
      "QUERY KEY () VECTOR embedding CANDIDATE KEY (id) VECTOR embedding METRIC dot K 1 AS n",
      "QUERY KEY (id) CANDIDATE KEY (id) VECTOR embedding METRIC dot K 1 AS n",
      roles + "METRIC approximate K 1 AS n",
      roles + "METRIC dot K 0 AS n",
      roles + "METRIC dot K -1 AS n",
      roles + "METRIC dot K 1.5 AS n",
      roles + "METRIC dot K @k AS n",
      roles + "METRIC dot K 9007199254740992 AS n",
      roles + "METRIC dot K 1 KEEP () AS n",
      roles + "METRIC dot K 1 KEEP (id + 1 AS x) AS n",
      roles + "METRIC dot K 1 KEEP (* AS all) AS n",
      roles + "METRIC dot K 1",
    ] {
    match
      parse_query(prefix + suffix, query_limits(), source_path="nearest.pipe") {
      Err({ span: Some(span), .. }) =>
        assert_eq(span.source_path, "nearest.pipe")
      _ => fail(suffix)
    }
  }
  let source = prefix + roles + "METRIC dot K 1 AS n"
  assert_true(
    parse_query(source, { ..query_limits(), max_syntax_nodes: 1, }) is Err(_),
  )
  assert_true(
    parse_query(source, { ..query_limits(), max_work: 20, }) is Err(_),
  )
  assert_true(
    parse_query("SELECT nearest, keep, infer FROM q", query_limits()) is Ok(_),
  )
}
