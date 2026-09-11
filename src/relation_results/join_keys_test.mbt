///|
test "join key dependencies survive alias deletion and Result order resolution" {
  let row = @schema.from_fields(
    [(Unqualified("id"), @contract.primitive(NumberType, nullable=false))],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let p = @pipeline.check_with_evidence(
    cursor(
      "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"left\",\"on\":[\"id\",\"id\"],\"select\":{\"a\":\"left.id\",\"b\":\"left.id\"}}},{\"drop\":[\"a\"],\"as\":\"out\"}]",
    ),
    [("l", @pipeline.KeyedInput(key)), ("r", @pipeline.KeyedInput(key))],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let r = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"b\"]}}"),
    limits(),
  ).unwrap()
  let order = resolve(r)
  assert_eq(@relation_results.publication_strategy(order), CandidateKey)
  let witness = @pipeline.candidate_key(p, Step(1)).unwrap()
  assert_eq(@evidence.key_join_dependency_count(witness), 2)
  assert_eq(@evidence.key_join_dependency_side(witness, 0), Some(@schema.Left))
  assert_eq(@evidence.key_join_dependency_side(witness, 1), Some(@schema.Right))
  assert_eq(@evidence.key_field_at(witness, 0).unwrap().name, Unqualified("b"))
}
