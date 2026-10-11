///|
test "independent complete typed subscript Programs reach common lowering" {
  for
    expression in [
      (
        #|{"subscript":{"value":{"array":[{"literal":2},{"literal":1},{"literal":2}]},"index":{"literal":1}}}
      ),
      (
        #|{"subscript":{"value":{"empty_array":{"items":{"type":"number","nullable":false}}},"index":{"literal":0}}}
      ),
    ] {
    let program = @program.parse(
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.typed_subscript\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"seed\",\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]}},{\"from\":\"seed\",\"derive\":{\"v\":" +
      expression +
      "}},{\"select\":[\"v\"],\"as\":\"selected\"}],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"v\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      construction_limits().program,
      format=Json,
    ).unwrap()
    let checked = match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(checked) => checked
      NeedsInputs(_) => fail("the authored Values control needs no acquisition")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
    let pipeline = @check.unit_pipeline(checked, 0).unwrap()
    let schema = @pipeline.output_schema(pipeline).unwrap()
    assert_eq(@schema.field_count(schema), 1)
    assert_eq(@schema.field_reference_name_at(schema, 0), Some("v"))
    assert_eq(
      @contract.stringify_checked(
        @schema.lookup(schema, Unqualified("v")).unwrap(),
        1000,
        100,
        10,
      ),
      "{\"nullable\":true,\"type\":\"number\"}",
    )
    let prepared = @lower.bind_parameters(
      @lower.prepare(pipeline, {
        max_nodes: 100,
        max_references: 100,
        max_work: 1000,
        max_identifier_bytes: 1000,
      }).unwrap(),
      None,
      max_parameters=0,
      max_name_bytes=0,
    ).unwrap()
    let result = @lower.lower_expression(prepared, 1, 0, {
      max_nodes: 1000,
      max_work: 10000,
      max_depth: 100,
      max_literal_nodes: 1000,
      max_literal_text_bytes: 10000,
    })
    assert_true(
      result is Ok(_),
      msg="the checked Program must reach common execution",
    )
  }
}
