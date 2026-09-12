///|
test "contract selection visits ordinary RelA operations without profile obligations" {
  let (identity, _, _) = prepared_identity_fixture(unused_operation=true)
  let requirements = collect_program_operation_requirements(
    close_program_expressions(identity, 10000000, 100).unwrap(),
    10000000,
    100,
  ).unwrap()
  let profiles = resolution_profiles(requirements)
  assert_eq(operation_profile_links_count(profiles), 0)
  let usage = program_identity_usage(identity)
  let mut unused = 0
  let mut visits = 0
  let mut operations = 0
  for stage in 0..<program_identity_stage_count(identity) {
    let count = program_identity_producer_count(identity, stage).unwrap()
    assert_true(count > 0)
    visits += count
    for visit in 0..<count {
      let pipeline = program_identity_producer_at(identity, stage, visit).unwrap()
      assert_true(
        physical_equal(
          pipeline,
          program_identity_producer_at(identity, stage, visit).unwrap(),
        ),
      )
      for i in 0..<@pipeline.step_count(pipeline) {
        let step = @pipeline.step_at(pipeline, i).unwrap()
        operations += 1
        if step.binding_name == Some("unused") {
          unused += 1
        }
        assert_eq(@pipeline.operation_profile_count(step.operation), 1)
        let profile = @pipeline.operation_profile_at(step.operation, 0).unwrap()
        assert_eq(profile, @pipeline.RelA)
        assert_eq(@pipeline.operation_profile_adopted_law_count(profile), 2)
        assert_eq(
          @pipeline.operation_profile_adopted_law_at(profile, 0),
          Some(@pipeline.RelaScalar),
        )
        assert_eq(
          @pipeline.operation_profile_adopted_law_at(profile, 1),
          Some(@pipeline.RelaPrimitive),
        )
      }
    }
    for invalid in [-2147483648, -1, count, 2147483647] {
      assert_true(
        program_identity_producer_at(identity, stage, invalid) is None,
      )
    }
  }
  assert_true(visits >= 2)
  assert_true(operations >= 3)
  assert_true(unused > 0)
  assert_eq(program_identity_usage(identity), usage)
  for invalid in [-2147483648, -1, 2, 2147483647] {
    assert_true(program_identity_producer_count(identity, invalid) is None)
    assert_true(program_identity_producer_at(identity, invalid, 0) is None)
  }
}

///|
test "producer reads retain the source Program owner rather than matching hashes" {
  let (first, _, _) = prepared_identity_fixture()
  let (second, _, _) = prepared_identity_fixture()
  assert_eq(
    program_identity_definition_cid(first),
    program_identity_definition_cid(second),
  )
  for stage in 0..<2 {
    let count = program_identity_producer_count(first, stage).unwrap()
    assert_eq(program_identity_producer_count(second, stage), Some(count))
    for visit in 0..<count {
      let a = program_identity_producer_at(first, stage, visit).unwrap()
      let b = program_identity_producer_at(second, stage, visit).unwrap()
      assert_true(!physical_equal(a, b))
      assert_eq(@pipeline.step_count(a), @pipeline.step_count(b))
    }
  }
}
