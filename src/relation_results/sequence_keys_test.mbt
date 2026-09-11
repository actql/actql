///|
test "nonoverlapping sequence identity reaches Result publication" {
  let row = @schema.from_fields(
    [(Unqualified("id"), @contract.primitive(NumberType, nullable=false))],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  let p = @pipeline.check(
    cursor(
      "[{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"id\",\"pattern\":[{\"as\":\"begin\",\"where\":\"true\"},{\"as\":\"end\",\"where\":\"true\"}],\"within\":1000,\"overlap\":\"disallow\",\"contiguity\":\"adjacent\"}},{\"select\":[{\"id\":\"end_id\"}],\"as\":\"out\"}]",
    ),
    [("rows", row)],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let r = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"out\",\"fields\":[\"id\"],\"order_by\":[{\"id\":\"asc\"}]}}",
    ),
    limits(),
  ).unwrap()
  let order = resolve(r)
  let witness = @relation_results.publication_key(order).unwrap()
  assert_eq(@evidence.key_origin(witness), SequenceResult)
  assert_eq(@evidence.key_field_at(witness, 0).unwrap().name, Unqualified("id"))
  assert_true(@evidence.key_sequence_producer(witness) is Some(_))
  assert_eq(@evidence.key_pending(witness), [ValidateKeyProducer])
}
