///|
test "public Result and ordering references require schema guaranteed presence" {
  let schema = @schema.from_presence_fields(
    [
      (
        Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
        Required,
      ),
      (
        Unqualified("p"),
        @contract.primitive(NumberType, nullable=true),
        Conditional,
      ),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  let pipeline = @pipeline.check(cursor("[]"), [("rows", schema)], None, None, {
    max_steps: 10,
    max_work: 10000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
  assert_true(
    @relation_results.check(
      pipeline,
      cursor("{\"answer\":{\"from\":\"rows\",\"fields\":[\"id\"]}}"),
      limits(),
    )
    is Ok(_),
  )
  for
    body in [
      "{\"answer\":{\"from\":\"rows\",\"fields\":[\"p\"]}}", "{\"answer\":{\"from\":\"rows\",\"fields\":[\"id\"],\"order_by\":[{\"p\":\"asc\"}]}}",
    ] {
    assert_true(
      @relation_results.check(pipeline, cursor(body), limits())
      is Err({ kind: PresenceRequired("p"), .. }),
    )
  }
}
