///|
test "whole-row and keyed distinct preserve only existing occurrence order" {
  let row = @schema.from_fields(
    [(Unqualified("id"), @contract.primitive(NumberType, nullable=false))],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  for body in ["true", "[\"id\"]"] {
    for ordered in [false, true] {
      let prefix = if ordered {
        "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2},{\"id\":1},{\"id\":2}]},\"as\":\"seed\"},"
      } else {
        ""
      }
      let p = @pipeline.check(
        cursor(
          "[" +
          prefix +
          "{\"distinct\":" +
          body +
          "},{\"take\":1,\"as\":\"out\"}]",
        ),
        [("rows", row)],
        None,
        None,
        ranking_limits(),
      ).unwrap()
      let i = if ordered { 1 } else { 0 }
      assert_eq(@pipeline.logical_order(p, Step(i)) is Some(_), ordered)
      if ordered {
        let order = @pipeline.take_order(p, i + 1).unwrap()
        assert_eq(@pipeline.order_origin(order), Step(0))
        assert_true(@pipeline.order_key_completion(order) is None)
        let r = @relation_results.check(
          p,
          cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"id\"]}}"),
          limits(),
        ).unwrap()
        assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
      }
    }
  }
}
