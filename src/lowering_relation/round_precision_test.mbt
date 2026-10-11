///|
test "precision rounding lowers to ordered binary bodies without rewriting unary nodes" {
  for
    (name, op) in [
      ("round", @lowering_relation.RoundAt),
      ("trunc", @lowering_relation.TruncAt),
    ] {
    for position in ["2", "0", "324", "-309"] {
      let owner = expression_pipeline(
        ",{\"derive\":{\"value\":{\"" +
        name +
        "\":[{\"literal\":1.235},{\"literal\":" +
        position +
        "}]}}}",
      )
      let lowered = @lowering_relation.lower_expression(
        owner,
        1,
        0,
        expression_limits(),
      ).unwrap()
      assert_true(
        @lowering_relation.expression_body(lowered)
        is @lowering_relation.Binary(actual, _, _) &&
        actual == op,
      )
      assert_eq(
        expression_wire(lowered),
        "{\"body\":[{\"body\":1.235,\"op\":\"literal\"},{\"body\":" +
        position +
        ",\"op\":\"literal\"}],\"op\":\"" +
        name +
        "\"}",
      )
    }
  }
}
