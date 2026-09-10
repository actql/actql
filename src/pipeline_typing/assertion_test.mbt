///|
test "assertions on qualified join fields retain obligations after projection" {
  let p = join_pipeline(
    "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"left\",\"on\":\"id\"}},{\"assert_rows\":{\"unique_by\":[\"right.id\"]}},{\"assert_rows\":{\"where\":\"right.amount > 0\"}},{\"select\":[{\"id\":\"left.id\"}],\"as\":\"out\"}]",
  ).unwrap()
  for i in [1, 2] {
    let step = @pipeline_typing.step_at(p, i).unwrap()
    assert_true(
      @schema.lookup(
        @pipeline_typing.step_schema(step).unwrap(),
        Qualified(Right, "id"),
      ).unwrap().nullable,
    )
    match step.operation {
      Unary(value) => {
        assert_eq(@relation.operation(value), AssertRows)
        let pending = @relation.pending_validations(value)
        assert_eq(pending[0].kind, AtomicRowAssertion)
        assert_eq(pending[1].kind, AssertionConsumption)
      }
      _ => fail("expected assertion")
    }
  }
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 1)
  assert_eq(@pipeline_typing.lookup(p, "out"), Some(Step(3)))
}
