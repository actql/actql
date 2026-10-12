///|
test "canonical vector score SQL and Pipe match the independent common expression" {
  for metric in ["cosine", "dot", "l2"] {
    let expected = "{\"vector_score\":{\"left\":{\"field\":\"left_vector\"},\"right\":{\"field\":\"right_vector\"},\"metric\":\"" +
      metric +
      "\"}}"
    for
      text in [
        "SELECT id, vector_score(left_vector,right_vector,'" +
        metric +
        "') AS value FROM vectors ORDER BY id",
        "FROM vectors |> SELECT id, vector_score(left_vector,right_vector,'" +
        metric +
        "') AS value |> ORDER BY id",
      ] {
      let actual = compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        vector_scalar_context(),
        construction_limits(),
      ).unwrap()
      guard @json.parse(with_carrier_argument(actual, "derive"))
        is Object(fields) else {
        fail("derived score")
      }
      assert_eq(fields.length(), 1)
      for (_, value) in fields {
        assert_eq(value, @json.parse(expected))
      }
      match
        @check.check_parsed(
          actual,
          check_environment(veca=true),
          None,
          check_limits(),
        ) {
        Checked(checked) => {
          let schema = @pipeline.output_schema(
            @check.unit_pipeline(checked, 0).unwrap(),
          ).unwrap()
          assert_eq(@schema.field_reference_name_at(schema, 0), Some("id"))
          assert_eq(@schema.field_reference_name_at(schema, 1), Some("value"))
          assert_eq(
            @contract.stringify_checked(
              @schema.lookup(schema, Unqualified("value")).unwrap(),
              1000,
              100,
              10,
            ),
            "{\"nullable\":true,\"type\":\"number\"}",
          )
        }
        Rejected(issue) => raise @check.diagnostic_cause(issue)
        NeedsInputs(_) => fail("closed typed score")
      }
    }
  }
}
