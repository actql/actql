///|
// Temporary diagnostic retained with the handoff, not a permanent assertion
// that these supported language operations must remain unimplemented.
test "predicate boundary diagnostic records the first shared expression refusal" {
  for
    (name, expression) in [
      (
        "between", "{\"between\":[{\"literal\":2},{\"literal\":1},{\"literal\":3}]}",
      ),
      ("like", "{\"like\":[{\"literal\":\"abc\"},{\"literal\":\"a%\"}]}"),
      ("like-null-left", "{\"like\":[{\"literal\":null},{\"literal\":\"a%\"}]}"),
    ] {
    let owner = expression_pipeline(",{\"derive\":{\"v\":" + expression + "}}")
    match
      @lowering_relation.lower_expression(owner, 1, 0, expression_limits()) {
      Ok(_) => println("PREDICATE_BOUNDARY " + name + " implemented")
      Err(issue) =>
        match issue.kind {
          ExpressionNotImplemented(tag) =>
            println(
              "PREDICATE_BOUNDARY " +
              name +
              " ExpressionNotImplemented(" +
              tag +
              ")",
            )
          PendingValidation(PatternValidation(tag)) =>
            println(
              "PREDICATE_BOUNDARY " +
              name +
              " PendingValidation(PatternValidation(" +
              tag +
              "))",
            )
          _ =>
            fail("unexpected refusal; inspect before classifying the failure")
        }
    }
  }
}
