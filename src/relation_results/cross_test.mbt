///|
test "explicit cross projection flows to a named Result" {
  let p = @pipeline.check(
    cursor(
      "[{\"cross_join\":{\"with\":\"rows\",\"select\":{\"left_id\":\"left.id\",\"right_id\":\"right.id\"}},\"as\":\"product\"}]",
    ),
    [("rows", @schema.from_object(input()).unwrap())],
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
    cursor(
      "{\"out\":{\"from\":\"product\",\"fields\":[\"left_id\",\"right_id\"]}}",
    ),
    limits(),
  ).unwrap()
  assert_eq(
    @relation_results.fields(@relation_results.result_at(results, 0).unwrap()),
    ["left_id", "right_id"],
  )
}
