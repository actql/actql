///|
fn create_projection_program(effect : String) -> @program.Program {
  // Independent canonical input: the same retained original computation and
  // original Mapping, changing only the existing create selector alternative.
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.create_projection\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"name\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"name\":\"original\"}]},\"as\":\"rows\"}],\"results\":{\"prepared\":{\"from\":\"rows\",\"fields\":[\"name\"]}},\"effects\":{\"write\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\"," +
    effect +
    "}}}}],\"results\":{}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "legacy canonical create keeps raw payload separate from original result row mapping" {
  let inline = create_projection_program("\"payload\":{\"Name\":\"original\"}")
  assert_true(insert_static_result(inline, "subset") is Ok(_))
  let rows = create_projection_program("\"from\":{\"result\":\"prepared\"}")
  guard insert_static_result(rows, "subset") is Err(MappingRules(issue)) else {
    fail("original row mapping must still require its declared city input")
  }
  assert_eq(
    @stage_results.effect_mapping_rule_issue_kind(issue),
    MissingResultField("city"),
  )
  // This is the original closed reader's refusal. A future explicit per-row
  // projection must not reinterpret legacy raw payload as an expression map.
  let both = create_projection_program(
    "\"from\":{\"result\":\"prepared\"},\"payload\":{\"Name\":\"original\"}",
  )
  assert_true(@program.collect_effect_headers(both, 1, 1000) is Err(_))
}
