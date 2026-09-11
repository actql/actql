///|
test "array and column expansion retain occurrence order rather than inventing keys" {
  let number = @contract.primitive(NumberType, nullable=false)
  let array = @contract.array_contract(number, nullable=false).unwrap()
  let row = @schema.from_fields(
    [(Unqualified("items"), array)],
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  for
    operation in [
      "\"unnest\":{\"column\":\"items\",\"as\":\"item\"}", "\"unnest\":{\"column\":\"items\",\"as\":\"item\",\"outer\":true}",
      "\"unpivot\":{\"columns\":[\"items\",\"items\"],\"name_column\":\"name\",\"value_column\":\"item\"}",
    ] {
    for ordered in [false, true] {
      let prefix = if ordered {
        "{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},{\"derive\":{\"items\":{\"array\":[{\"literal\":1},{\"literal\":2}]}}},{\"select\":[\"items\"]},"
      } else {
        ""
      }
      let p = @pipeline.check(
        cursor(
          "[" +
          prefix +
          "{" +
          operation +
          "},{\"select\":[\"item\"]},{\"take\":1,\"as\":\"out\"}]",
        ),
        [("rows", row)],
        None,
        None,
        ranking_limits(),
      ).unwrap()
      let i = if ordered { 3 } else { 0 }
      assert_eq(@pipeline.logical_order(p, Step(i)) is Some(_), ordered)
      assert_eq(@pipeline.take_order(p, i + 2) is Some(_), ordered)
      if ordered {
        let order = @pipeline.take_order(p, i + 2).unwrap()
        assert_eq(@pipeline.order_origin(order), Step(i))
        assert_eq(@pipeline.order_dependency_count(order), 1)
        assert_eq(@pipeline.order_dependency_at(order, 0), Some(Step(2)))
        assert_true(
          @pipeline.order_producer(order).unwrap().operation is Unary(_),
        )
        let r = @relation_results.check(
          p,
          cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"item\"]}}"),
          limits(),
        ).unwrap()
        assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
      }
    }
  }
}
