///|
test "NEAREST keeps both or either typed Carrier role pair optional" {
  for roles in [
    "", "QUERY KEY (request_id) VECTOR embedding ",
    "CANDIDATE KEY (c.item_id) VECTOR c.embedding ",
    "QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding ",
  ] {
    let text = "FROM query_vectors |> NEAREST candidate_vectors AS c " + roles + "METRIC cosine K 2 AS hits"
    guard parse_query(text, query_limits()) is Ok(query) else {
      fail("An optional complete role pair is valid syntax: " + text)
    }
    assert_true(operation_at(query, 0) is Some(Nearest(_)))
  }
}

///|
test "NEAREST refuses a partial KEY VECTOR role pair" {
  for roles in [
    "QUERY KEY (id) ", "QUERY VECTOR embedding ",
    "CANDIDATE KEY (c.id) ", "CANDIDATE VECTOR c.embedding ",
    "QUERY KEY (id) VECTOR embedding CANDIDATE KEY (c.id) ",
    "QUERY KEY () VECTOR embedding ",
  ] {
    let text = "FROM q |> NEAREST candidates AS c " + roles + "METRIC cosine K 1 AS hit"
    guard parse_query(text, query_limits(), source_path="typed-nearest.sql")
      is Err({ span: Some(span), .. }) else {
      fail("A missing half cannot become an inferred role: " + text)
    }
    assert_eq(span.source_path, "typed-nearest.sql")
  }
}
