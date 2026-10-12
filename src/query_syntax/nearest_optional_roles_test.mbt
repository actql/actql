///|
test "NEAREST keeps both or either typed Carrier role pair optional" {
  for
    roles in [
      "", "QUERY KEY (request_id) VECTOR embedding ", "CANDIDATE KEY (c.item_id) VECTOR c.embedding ",
      "QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding ",
    ] {
    let text = "FROM query_vectors |> NEAREST candidate_vectors AS c " +
      roles +
      "METRIC cosine K 2 AS hits"
    guard parse_query(text, query_limits()) is Ok(query) else {
      fail("An optional complete role pair is valid syntax: " + text)
    }
    guard operation_at(query, 0) is Some(Nearest(clause)) else {
      fail("the role pair belongs to the typed nearest clause")
    }
    assert_eq(clause.query_roles is Some(_), roles.contains("QUERY"))
    assert_eq(clause.candidate_roles is Some(_), roles.contains("CANDIDATE"))
  }
}

///|
test "NEAREST refuses a partial KEY VECTOR role pair" {
  for
    roles in [
      "QUERY KEY (id) ", "QUERY VECTOR embedding ", "CANDIDATE KEY (c.id) ", "CANDIDATE VECTOR c.embedding ",
      "QUERY KEY (id) VECTOR embedding CANDIDATE KEY (c.id) ", "QUERY KEY () VECTOR embedding ",
    ] {
    let text = "FROM q |> NEAREST candidates AS c " +
      roles +
      "METRIC cosine K 1 AS hit"
    guard parse_query(text, query_limits(), source_path="typed-nearest.sql")
      is Err({ span: Some(span), .. }) else {
      fail("A missing half cannot become an inferred role: " + text)
    }
    assert_eq(span.source_path, "typed-nearest.sql")
  }
}

///|
test "optional NEAREST pair arrays cannot mutate the admitted Query" {
  let query = parse_query(
    "FROM q |> NEAREST c AS r QUERY KEY (tenant, id) VECTOR embedding METRIC dot K 1 AS hit",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 0) is Some(Nearest(clause)) else { fail("nearest") }
  clause.query_roles.unwrap().keys[0].clear()
  clause.query_roles.unwrap().keys.clear()
  guard operation_at(query, 0) is Some(Nearest(fresh)) else { fail("nearest") }
  assert_eq(fresh.query_roles.unwrap().keys.length(), 2)
  assert_eq(fresh.query_roles.unwrap().keys[0][0].value, "tenant")
  assert_true(fresh.candidate_roles is None)
}
