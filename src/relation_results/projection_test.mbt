///|
test "only explicit event projection can publish a typed Relation result" {
  let event = @carrier.events(
    @carrier.rows(
      [
        (
          Unqualified("id"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("at"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap(),
    id=Unqualified("id"),
    time=Unqualified("at"),
  ).unwrap()
  let p = @pipeline.check_carriers(
    cursor("[{\"events\":true,\"as\":\"rows\"}]"),
    [("input", event)],
    None,
    None,
    {
      max_steps: 100,
      max_work: 10000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let accepted = @relation_results.check(
    p,
    cursor("{\"result\":{\"from\":\"rows\",\"fields\":[\"id\"]}}"),
    limits(),
  ).unwrap()
  assert_eq(@relation_results.count(accepted), 1)
  let result = @relation_results.result_at(accepted, 0).unwrap()
  assert_true(
    @schema.lookup(@relation_results.output_schema(result), Unqualified("id")).unwrap().shape
    is Number,
  )
  let rejected = @relation_results.check(
    p,
    cursor("{\"result\":{\"from\":\"input\",\"fields\":[\"id\"]}}"),
    limits(),
  ).unwrap_err()
  assert_eq(rejected.kind, WrongCarrier(EventsKind))
}
