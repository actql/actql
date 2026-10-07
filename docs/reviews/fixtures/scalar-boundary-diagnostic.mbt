///|
// Temporary diagnostic; retained under docs/reviews after execution. A
// currently missing operation is reported, not fixed as an expected refusal.
test "scalar boundary diagnostic records the first shared expression refusal" {
  for
    (name, expression) in [
      ("sqrt", "{\"sqrt\":{\"literal\":9}}"),
      ("lower", "{\"lower\":{\"literal\":\"É\"}}"),
      ("upper", "{\"upper\":{\"literal\":\"é\"}}"),
      ("trim", "{\"trim\":{\"literal\":\" value \"}}"),
    ] {
    let owner = expression_pipeline(", {\"derive\":{\"v\":" + expression + "}}")
    match
      @lowering_relation.lower_expression(owner, 1, 0, expression_limits()) {
      Ok(_) => println("SCALAR_BOUNDARY " + name + " implemented")
      Err(issue) =>
        match issue.kind {
          ExpressionNotImplemented(tag) =>
            println(
              "SCALAR_BOUNDARY " +
              name +
              " ExpressionNotImplemented(" +
              tag +
              ")",
            )
          _ =>
            fail(
              "unexpected refusal; inspect the diagnostic before classifying it",
            )
        }
    }
  }
}
