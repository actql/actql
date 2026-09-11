///|
test "empty pivot values depend on first occurrence order except for the global group" {
  let number = @contract.primitive(NumberType, nullable=false)
  let text = @contract.primitive(StringType, nullable=false)
  let row = @schema.from_fields(
    [
      (Unqualified("id"), number),
      (Unqualified("column"), text),
      (Unqualified("value"), number),
    ],
    max_fields=3,
    max_name_bytes=20,
  ).unwrap()
  for ordered in [false, true] {
    for index in ["[]", "[\"id\"]"] {
      for values in ["[]", "[\"a\"]"] {
        let prefix = if ordered {
          "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"column\":{\"type\":\"string\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2,\"column\":\"a\",\"value\":1},{\"id\":1,\"column\":\"a\",\"value\":2}]},\"as\":\"seed\"},"
        } else {
          ""
        }
        let p = @pipeline.check(
          cursor(
            "[" +
            prefix +
            "{\"pivot\":{\"index\":" +
            index +
            ",\"column\":\"column\",\"values\":" +
            values +
            ",\"value\":\"value\",\"aggregate\":\"sum\"},\"as\":\"out\"}]",
          ),
          [("rows", row)],
          None,
          None,
          ranking_limits(),
        ).unwrap()
        let i = if ordered { 1 } else { 0 }
        let needs_input = values == "[]" && index != "[]"
        let order = @pipeline.logical_order(p, Step(i))
        assert_eq(order is Some(_), ordered || !needs_input)
        if order is Some(v) {
          assert_eq(@pipeline.order_origin(v), Step(i))
          assert_eq(
            @pipeline.order_dependency_count(v),
            if needs_input {
              1
            } else {
              0
            },
          )
          if needs_input {
            assert_eq(@pipeline.order_dependency_at(v, 0), Some(Step(0)))
          }
        }
      }
    }
  }
}
