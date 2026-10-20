///|
test "original Group audit charges every key and aggregate and rejects equal prefixed keys" {
  let program = checked_direct_program_fixture(
    group_body="{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\"},\"hi\":{\"fn\":\"max\",\"field\":\"id\"}}}",
  )
  guard @pipeline.step_at(program.units[0].pipeline, 0).unwrap().operation
    is @pipeline.Unary(operation) else {
    fail("expected original ordinary Group")
  }
  assert_eq(audit_local_completion_free_group(operation, 3), Some(0))
  assert_eq(audit_local_completion_free_group(operation, 4), Some(1))
  assert_true(audit_local_completion_free_group(operation, 2) is None)
  assert_true(audit_local_completion_free_group(operation, 0) is None)
  let prefixed = @relation.check_group_with_prefix(
    @relation.source(operation),
    @relation.input_schema(operation),
    [@schema.Unqualified("id")],
    None,
    {
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_tokens: 10000,
    },
  ).unwrap()
  assert_eq(
    @relation.group_key_count(@relation.group(operation).unwrap()),
    @relation.group_key_count(@relation.group(prefixed).unwrap()),
  )
  assert_true(audit_local_completion_free_group(prefixed, 10000) is None)
}

///|
test "Group inventory refuses numeric reductions even with their actual numeric owner" {
  let profile = numeric_profile_fixture()
  for name in ["sum", "avg"] {
    let program = checked_direct_program_fixture(
      group_body="{\"by\":[\"id\"],\"aggregates\":{\"total\":{\"fn\":\"" +
        name +
        "\",\"field\":\"id\"}}}",
      numeric_profile=Some(profile),
    )
    guard @pipeline.step_at(program.units[0].pipeline, 0).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("expected original numeric Group")
    }
    assert_true(audit_local_completion_free_group(operation, 10000) is None)
  }
}
