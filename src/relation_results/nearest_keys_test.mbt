///|
test "nearest positional identities complete publication order through surviving aliases" {
  let rows = @carrier.rows(
    [
      (Unqualified("a"), Some(@contract.primitive(NumberType, nullable=false))),
      (Unqualified("b"), Some(@contract.primitive(StringType, nullable=false))),
      (
        Unqualified("v"),
        Some(@contract.vector_contract(2, nullable=false).unwrap()),
      ),
    ],
    field_set=Closed,
    max_fields=3,
    max_name_bytes=3,
  ).unwrap()
  let vector = @carrier.vectors(
    rows,
    ids=[Unqualified("b"), Unqualified("a")],
    components=Unqualified("v"),
    max_identity_fields=2,
  ).unwrap()
  let p = @pipeline.check_carriers(
    cursor(
      "[{\"nearest\":{\"queries\":\"v\",\"metric\":\"dot\",\"k\":2}},{\"select\":[{\"a\":\"candidate_id\"},{\"b\":\"candidate_id\"},\"query_id\",\"score\"]},{\"drop\":[\"a\"],\"as\":\"out\"}]",
    ),
    [("v", vector)],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"out\",\"fields\":[\"query_id\",\"b\"],\"order_by\":[{\"score\":\"desc\"}]}}",
    ),
    limits(),
  ).unwrap()
  let order = resolve(results)
  let key = @relation_results.publication_key(order).unwrap()
  assert_eq(@evidence.key_origin(key), NearestResult)
  assert_true(@evidence.key_nearest_producer(key) is Some(_))
  assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
  assert_eq(@evidence.key_field_count(key), 2)
  for i in 0..<2 {
    let vectors = @evidence.key_field_at(key, i).unwrap().positional_identity.unwrap()
    assert_eq(
      @carrier.vector_identity_at(vectors, 0).unwrap().name,
      Unqualified("b"),
    )
    assert_eq(
      @carrier.vector_identity_at(vectors, 1).unwrap().name,
      Unqualified("a"),
    )
  }
}
