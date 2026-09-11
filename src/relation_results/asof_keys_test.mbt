///|
test "as-of identity evidence survives projection and Result publication checking" {
  let row = @schema.from_fields(
    [(Unqualified("id"), @contract.primitive(NumberType, nullable=false))],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  let p = @pipeline.check(
    cursor(
      "[{\"from\":\"l\",\"asof_join\":{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"id\",\"right_time\":\"id\",\"direction\":\"backward\",\"tolerance\":1,\"select\":{\"a\":\"left.id\",\"b\":\"left.id\"}}},{\"drop\":[\"a\"],\"as\":\"out\"}]",
    ),
    [("l", row), ("r", row)],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let r = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"out\",\"fields\":[\"b\"],\"order_by\":[{\"b\":\"asc\"}]}}",
    ),
    limits(),
  ).unwrap()
  let order = resolve(r)
  let witness = @relation_results.publication_key(order).unwrap()
  assert_eq(@evidence.key_origin(witness), AsOfResult)
  assert_eq(@evidence.key_field_at(witness, 0).unwrap().name, Unqualified("b"))
  assert_true(@evidence.key_asof_producer(witness) is Some(_))
  assert_true(@evidence.key_pending(witness).contains(ValidateKeyProducer))
}
