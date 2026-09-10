///|
test "sequence match schema feeds Result selection without copying payload" {
  let row = @schema.from_fields(
    [
      (Unqualified("id"), @contract.primitive(NumberType, nullable=false)),
      (Unqualified("time"), @contract.primitive(TimestampType, nullable=false)),
    ],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let p = @pipeline.check(
    cursor(
      "[{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"time\",\"pattern\":[{\"as\":\"a\",\"where\":{\"literal\":true}},{\"as\":\"b\",\"where\":{\"literal\":true}}],\"within\":\"1s\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"},\"as\":\"matches\"}]",
    ),
    [("rows", row)],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_nodes: 100000,
      max_text_bytes: 100000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"matches\",\"fields\":[\"a_id\",\"b_time_ms\"]}}",
    ),
    limits(),
  ).unwrap()
  let result = @relation_results.result_at(results, 0).unwrap()
  assert_eq(@relation_results.fields(result), ["a_id", "b_time_ms"])
  assert_eq(@relation_results.pending_validations(result), [
    TotalDeterministicOrder,
  ])
  assert_true(
    @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"matches\",\"fields\":[\"time\"]}}"),
      limits(),
    )
    is Err({ kind: UnknownField("time"), .. }),
  )
}
