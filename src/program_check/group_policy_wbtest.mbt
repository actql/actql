///|
test "acquired group publication retains source and aggregate policy occurrences" {
  for
    (body, missing) in [
      ("{\"by\":[\"id\"],\"aggregates\":{}}", false),
      ("{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}", false),
      ("{\"by\":[],\"aggregates\":{\"id\":{\"fn\":\"count\"}}}", false),
      (
        "{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\",\"expr\":\"id\",\"filter\":\"id = id\"}}}",
        false,
      ),
      (
        "{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\",\"expr\":\"1\",\"filter\":\"FALSE\"}}}",
        true,
      ),
    ] {
    let program = checked_direct_program_fixture(group_body=body)
    let policy = publication_source_policy(
      unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    assert_eq(publication_policy_group_count(policy), 1)
    let occurrence = publication_policy_group_at(policy, 0).unwrap()
    assert_eq(occurrence.step, 0)
    assert_eq(occurrence.unknown_provenance, missing)
    guard @pipeline.step_at(program.units[0].pipeline, 0).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("expected group")
    }
    assert_true(physical_equal(occurrence.operation, operation))
    assert_true(
      physical_equal(occurrence.group, @relation.group(operation).unwrap()),
    )
    assert_true(
      physical_equal(
        publication_policy_source_at(policy, 0).unwrap(),
        policy.prerequisite.unwrap(),
      ),
    )
    assert_true(publication_policy_group_at(policy, -1) is None)
    assert_true(publication_policy_group_at(policy, 1) is None)
    let writer = @encode.writer(10000, 100, 10)
    emit_publication_source_policy(policy, writer)
    assert_eq(
      "sha256:" + @sha.text_hex(@encode.finish(writer)).unwrap(),
      policy.cid,
    )
  }
}
