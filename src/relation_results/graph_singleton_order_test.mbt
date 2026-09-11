///|
test "graph comparison singleton order supports structured Result publication" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let g = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    empty,
    empty,
    labels=Some([]),
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  for (operation, field) in [("graph_diff", "delta"), ("graphs_equal", "equal")] {
    for right in ["a", "b"] {
      let p = @pipeline.check_carriers(
        cursor(
          "[{\"" +
          operation +
          "\":{\"with\":\"" +
          right +
          "\"},\"from\":\"a\"},{\"select\":[\"" +
          field +
          "\"]},{\"filter\":{\"literal\":false}},{\"take\":1,\"as\":\"out\"}]",
        ),
        [("a", g), ("b", g)],
        None,
        None,
        ranking_limits(),
      ).unwrap()
      for i in 0..<4 {
        let order = @pipeline.logical_order(p, Step(i)).unwrap()
        assert_eq(@pipeline.order_origin(order), Step(0))
        assert_eq(@pipeline.order_dependency_count(order), 0)
        let inputs = @pipeline.input_occurrences(
          @pipeline.order_producer(order),
        )
        assert_eq(inputs.length(), 2)
        assert_eq(inputs[0].target, Input(0))
        assert_eq(inputs[1].target, Input(if right == "a" { 0 } else { 1 }))
      }
      let r = @relation_results.check(
        p,
        cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"" + field + "\"]}}"),
        limits(),
      ).unwrap()
      assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
    }
  }
}
