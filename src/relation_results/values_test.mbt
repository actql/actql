///|
test "empty generated Relation remains publishable with its declared schema" {
  let p = @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 100000,
      max_tokens: 0,
      max_depth: 100,
    },
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"seed\",\"fields\":[\"id\"]}}"),
    limits(),
  ).unwrap()
  assert_eq(
    @relation_results.target(@relation_results.result_at(results, 0).unwrap()),
    Step(0),
  )
}
