///|
test "ordered and deduplicated raw join output reaches Result without flattening" {
  for kind in ["inner", "left", "full", "semi", "anti"] {
    let p = joined_pipeline(
      kind,
      suffix=",{\"sort\":[{\"left.score\":\"desc\"}]},{\"take\":{\"count\":3,\"offset\":1}},{\"distinct\":true},{\"dedupe_rows\":{\"by\":[],\"order_by\":[{\"left.id\":\"asc\"}]}},{\"distinct\":[\"left.id\",\"left.score\"],\"as\":\"selected\"}",
    )
    let result = @relation_results.result_at(
      @relation_results.check(
        p,
        cursor(
          "{\"r\":{\"from\":\"selected\",\"fields\":[\"left.id\"],\"order_by\":[{\"left.score\":\"desc\"}]}}",
        ),
        limits(),
      ).unwrap(),
      0,
    ).unwrap()
    assert_eq(@relation_results.fields(result), ["left.id"])
    assert_eq(
      @schema.lookup(
        @relation_results.output_schema(result),
        Qualified(Left, "id"),
      ).unwrap().nullable,
      kind == "full",
    )
    assert_eq(@relation_results.order_by(result).unwrap()[0].nulls, Last)
    assert_eq(@relation_results.pending_validations(result), [
      TotalDeterministicOrder,
    ])
  }
}
