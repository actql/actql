///|
test "number extrema canonical lowering retains singletons repetitions and order" {
  for
    (name, op) in [
      ("greatest", @lowering_relation.Greatest),
      ("least", @lowering_relation.Least),
    ] {
    for
      (args, body, count) in [
        ("[{\"literal\":7}]", "[{\"body\":7,\"op\":\"literal\"}]", 1),
        (
          "[{\"literal\":1},{\"literal\":3},{\"literal\":1}]", "[{\"body\":1,\"op\":\"literal\"},{\"body\":3,\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"}]",
          3,
        ),
        (
          "[{\"literal\":null},{\"literal\":3}]", "[{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"},{\"body\":3,\"op\":\"literal\"}]",
          2,
        ),
        (
          "[{\"literal\":3},{\"literal\":1},{\"literal\":1}]", "[{\"body\":3,\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"}]",
          3,
        ),
        (
          "[{\"literal\":null},{\"literal\":null}]", "[{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"},{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"}]",
          2,
        ),
      ] {
      let owner = expression_pipeline(
        ",{\"derive\":{\"value\":{\"" + name + "\":" + args + "}}}",
      )
      let lowered = @lowering_relation.lower_expression(
        owner,
        1,
        0,
        expression_limits(),
      ).unwrap()
      assert_true(
        @lowering_relation.expression_body(lowered)
        is @lowering_relation.Many(actual, children) &&
        actual == op &&
        children.length() == count,
      )
      let expected = "{\"body\":" + body + ",\"op\":\"" + name + "\"}"
      assert_eq(expression_wire(lowered), expected)
      let exact = @encode.writer(expected.length(), 100, 10)
      @lowering_relation.emit_expression(lowered, exact)
      assert_eq(@encode.finish(exact), expected)
      let short = @encode.writer(expected.length() - 1, 100, 10)
      let exceeded = try {
        @lowering_relation.emit_expression(lowered, short)
        false
      } catch {
        @encode.OutputLimit => true
        _ => false
      }
      assert_true(exceeded)
    }
  }
}
