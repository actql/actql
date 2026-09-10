///|
test "set output can be explicitly published without changing its schema" {
  for op in ["except", "intersect"] {
    let p = @pipeline.check(
      cursor(
        "[{\"" +
        op +
        "\":{\"with\":\"rows\",\"duplicates\":\"distinct\"},\"as\":\"subset\"}]",
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
    let result = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"subset\",\"fields\":[\"id\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(
      @relation_results.target(@relation_results.result_at(result, 0).unwrap()),
      Step(0),
    )
  }
}
