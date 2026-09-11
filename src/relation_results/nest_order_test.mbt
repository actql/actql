///|
test "nest preserves parent order independently of child order resolution" {
  let row = @schema.from_fields(
    [(Unqualified("id"), @contract.primitive(NumberType, nullable=false))],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  for parent in ["seed", "raw"] {
    for child in ["seed", "raw"] {
      let p = @pipeline.check(
        cursor(
          "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2},{\"id\":1}]},\"as\":\"seed\"},{\"nest\":{\"with\":\"" +
          child +
          "\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\"]},\"from\":\"" +
          parent +
          "\"},{\"select\":[\"items\"]},{\"take\":1,\"as\":\"out\"}]",
        ),
        [("raw", row)],
        None,
        None,
        ranking_limits(),
      ).unwrap()
      assert_eq(
        @pipeline.logical_order(p, Step(1)) is Some(_),
        parent == "seed",
      )
      assert_eq(@pipeline.take_order(p, 3) is Some(_), parent == "seed")
      if parent == "seed" {
        let order = @pipeline.take_order(p, 3).unwrap()
        assert_eq(@pipeline.order_origin(order), Step(0))
        let r = @relation_results.check(
          p,
          cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"items\"]}}"),
          limits(),
        ).unwrap()
        assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
      }
    }
  }
}
