///|
test "window input proofs retain sparse claim coordinates and exact membership products" {
  for host_first in [false, true] {
    for (kind, factor) in [("fixed", 1L), ("sliding", 4L)] {
      let index = join_resolution_fixture(
        host_first~,
        window_body=Some(
          "\"time\":\"id\",\"kind\":\"" +
          kind +
          "\",\"size\":10,\"step\":3,\"offset\":-7",
        ),
      )
      let requirements = operation_resolution_requirements(index)
      let mut found = 0
      for i in 0..<operation_resolution_count(index) {
        let site = operation_requirements_at(requirements, i).unwrap()
        guard site.requirement
          is @pipeline.WindowRequirement(@window.ResolveMembershipBound) else {
          continue
        }
        found += 1
        let bounds = collect_window_membership_bounds(index, i, 10000000, 10).unwrap()
        assert_true(
          physical_equal(window_membership_bound_owner(bounds), index),
        )
        assert_eq(window_membership_bound_requirement(bounds), i)
        assert_eq(window_membership_bound_law(bounds), "actql.bound.row-window")
        assert_eq(window_membership_bound_maximum(bounds), Some(factor))
        assert_eq(
          window_membership_bound_options(bounds).maximum_per_input,
          factor,
        )
        assert_eq(window_membership_bound_candidate_count(bounds), 1)
        let candidate = window_membership_bound_candidate_at(bounds, 0).unwrap()
        assert_eq(candidate.maximum, factor)
        let (_, claim, _) = @capacity.target_membership_coordinates(
          candidate.input,
        )
        assert_eq(claim, if host_first { 1 } else { 0 })
        let rows = @capacity.target_membership_rows(candidate.input)
        assert_eq(@program.target_rows_value(rows), 1L)
        assert_eq(
          @program.target_rows_target(rows),
          window_membership_bound_execution(bounds).input,
        )
        assert_true(
          physical_equal(@program.target_rows_pipeline(rows), site.pipeline),
        )
        assert_true(window_membership_bound_candidate_at(bounds, -1) is None)
        assert_true(window_membership_bound_candidate_at(bounds, 1) is None)
        // The Host's value of one is not substituted for this Program product.
        assert_true(operation_resolution_at(index, i) is Some(Unresolved))
        let work = window_membership_bound_work(bounds)
        assert_true(
          collect_window_membership_bounds(index, i, work, 1) is Ok(_),
        )
        assert_true(
          collect_window_membership_bounds(index, i, work - 1, 1)
          is Err(BudgetExceeded),
        )
        assert_true(
          collect_window_membership_bounds(index, i, 10000000, 0)
          is Err(BudgetExceeded),
        )
      }
      assert_eq(found, 1)
      assert_true(
        collect_window_membership_bounds(index, -1, 10000000, 10)
        is Err(InvalidRequirement),
      )
      assert_true(
        collect_window_membership_bounds(index, 0, -1, 10) is Err(InvalidLimits),
      )
    }
  }
}

///|
test "window collection charges but does not adopt a proof for another input" {
  let index = join_resolution_fixture(
    host_first=true,
    window_from="joined",
    window_body=Some("\"time\":\"id\",\"kind\":\"fixed\",\"size\":10"),
  )
  let requirements = operation_resolution_requirements(index)
  let mut found = 0
  for i in 0..<operation_resolution_count(index) {
    guard operation_requirements_at(requirements, i).unwrap().requirement
      is @pipeline.WindowRequirement(@window.ResolveMembershipBound) else {
      continue
    }
    found += 1
    let bounds = collect_window_membership_bounds(index, i, 10000000, 0).unwrap()
    assert_eq(window_membership_bound_maximum(bounds), None)
    assert_eq(window_membership_bound_candidate_count(bounds), 0)
    let work = window_membership_bound_work(bounds)
    assert_true(collect_window_membership_bounds(index, i, work, 0) is Ok(_))
    assert_true(
      collect_window_membership_bounds(index, i, work - 1, 0)
      is Err(BudgetExceeded),
    )
  }
  assert_eq(found, 1)
}

///|
test "event membership bounds keep the Events law and occurrence input" {
  let index = join_resolution_fixture(
    host_first=true,
    window_events=true,
    window_body=Some("\"kind\":\"sliding\",\"size\":10,\"step\":3"),
  )
  let requirements = operation_resolution_requirements(index)
  let mut found = 0
  for i in 0..<operation_resolution_count(index) {
    let site = operation_requirements_at(requirements, i).unwrap()
    guard site.requirement
      is @pipeline.WindowRequirement(@window.ResolveMembershipBound) else {
      continue
    }
    found += 1
    let bounds = collect_window_membership_bounds(index, i, 10000000, 1).unwrap()
    assert_eq(window_membership_bound_law(bounds), "actql.bound.window-events")
    assert_eq(window_membership_bound_maximum(bounds), Some(4L))
    assert_eq(window_membership_bound_candidate_count(bounds), 1)
    let execution = window_membership_bound_execution(bounds)
    assert_true(@window.input(execution.window) is @carrier.EventValue(_))
    assert_eq(execution.input, @pipeline.Step(2))
    let candidate = window_membership_bound_candidate_at(bounds, 0).unwrap()
    let rows = @capacity.target_membership_rows(candidate.input)
    assert_eq(@program.checked_step(@program.target_rows_bound(rows)), 0)
    assert_eq(@capacity.target_membership_coordinates(candidate.input).1, 1)
    assert_true(operation_resolution_at(index, i) is Some(Unresolved))
  }
  assert_eq(found, 1)
}

///|
test "window membership factor without input proof does not invent zero or Host coverage" {
  let index = index_program_operation_resolutions(
    resolution_profiles(
      operation_order_fixture(
        scalar_steps(
          "{\"row_window\":{\"time\":\"id\",\"kind\":\"sliding\",\"size\":10,\"step\":3}}",
        ),
        tea=true,
      ),
    ),
    10000000,
    1000,
  ).unwrap()
  let requirements = operation_resolution_requirements(index)
  let mut found = 0
  for i in 0..<operation_resolution_count(index) {
    guard operation_requirements_at(requirements, i).unwrap().requirement
      is @pipeline.WindowRequirement(@window.ResolveMembershipBound) else {
      continue
    }
    found += 1
    let bounds = collect_window_membership_bounds(index, i, 10000000, 0).unwrap()
    assert_eq(window_membership_bound_maximum(bounds), None)
    assert_eq(window_membership_bound_candidate_count(bounds), 0)
    assert_eq(window_membership_bound_options(bounds).maximum_per_input, 4L)
    assert_true(operation_resolution_at(index, i) is Some(Unresolved))
  }
  assert_eq(found, 3)
}
