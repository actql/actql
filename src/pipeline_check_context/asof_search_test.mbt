///|
test "asof search retains sparse memberships and closes only its own search obligation" {
  for host_first in [false, true] {
    for kind in ["left", "inner"] {
      let index = join_resolution_fixture(host_first~, asof_kind=Some(kind))
      let requirements = operation_resolution_requirements(index)
      let linked = link_program_asof_search_limits(index, 10000000, 1, 2).unwrap()
      assert_eq(
        operation_resolution_unresolved_count(linked),
        operation_resolution_unresolved_count(index) - 1,
      )
      let mut found = 0
      for i in 0..<operation_resolution_count(index) {
        guard operation_resolution_at(linked, i)
          is Some(Execution(AsOfSearch(check))) else {
          continue
        }
        found += 1
        assert_true(
          physical_equal(
            check.site,
            operation_requirements_at(requirements, i).unwrap(),
          ),
        )
        assert_true(
          check.site.requirement is @pipeline.AsOfRequirement(ResolveSearchWork),
        )
        assert_true(
          physical_equal(asof_search_bound_owner(check.bounds), index),
        )
        assert_true(
          physical_equal(
            asof_search_bound_product(check.bounds).unwrap(),
            check.product,
          ),
        )
        assert_eq(@program.asof_search_upper(check.product), 1L)
        assert_eq(
          operation_execution_phase(AsOfSearch(check)),
          BeforeOperationInputUse,
        )
        assert_eq(
          operation_execution_failure(AsOfSearch(check)),
          RejectOperationOutput,
        )
        for side in 0..<2 {
          assert_eq(asof_search_bound_candidate_count(check.bounds, side), 1)
          let membership = asof_search_bound_candidate_at(check.bounds, side, 0).unwrap()
          assert_true(
            physical_equal(
              @capacity.target_membership_closure(membership),
              asof_search_bound_closure(check.bounds),
            ),
          )
          assert_true(
            physical_equal(
              @capacity.target_membership_rows(membership),
              @program.asof_search_bound_at(check.product, side).unwrap(),
            ),
          )
          assert_eq(
            @capacity.target_membership_coordinates(membership).1,
            if host_first {
              1
            } else {
              0
            },
          )
          assert_true(
            asof_search_bound_candidate_at(check.bounds, side, 1) is None,
          )
        }
        assert_true(asof_search_bound_candidate_at(check.bounds, -1, 0) is None)
        assert_true(operation_resolution_at(index, i) is Some(Unresolved))
        let used = asof_search_bound_work(check.bounds)
        assert_true(collect_asof_search_bounds(index, i, used, 2) is Ok(_))
        assert_true(
          collect_asof_search_bounds(index, i, used - 1, 2)
          is Err(BudgetExceeded),
        )
        assert_true(
          collect_asof_search_bounds(index, i, used, 1) is Err(BudgetExceeded),
        )
      }
      assert_eq(found, 1)
      let work = operation_resolution_work(linked)
      assert_true(link_program_asof_search_limits(index, work, 1, 2) is Ok(_))
      assert_true(
        link_program_asof_search_limits(index, work - 1, 1, 2)
        is Err(BudgetExceeded),
      )
      assert_true(
        link_program_asof_search_limits(index, work, 0, 2)
        is Err(BudgetExceeded),
      )
      assert_true(
        link_program_asof_search_limits(index, work, 1, 1)
        is Err(BudgetExceeded),
      )
      assert_true(
        link_program_asof_search_limits(linked, 10000000, 1, 2)
        is Err(ForeignEvidence),
      )
      let output = link_program_join_requirements(linked, 10000000, 4).unwrap()
      let mut output_count = 0
      for i in 0..<operation_resolution_count(output) {
        if operation_requirements_at(requirements, i).unwrap().requirement
          is @pipeline.AsOfRequirement(ResolveOutputLimit) {
          assert_true(operation_resolution_at(linked, i) is Some(Unresolved))
          assert_true(
            operation_resolution_at(output, i)
            is Some(Execution(JoinOutputLimit(_))),
          )
          output_count += 1
        }
      }
      assert_eq(output_count, 1)
    }
  }
}

///|
test "asof search cannot use an output ceiling as missing operand evidence" {
  let index = join_resolution_fixture(
    host_first=true,
    asof_kind=Some("left"),
    interval_with="joined",
  )
  let requirements = operation_resolution_requirements(index)
  let mut found = 0
  for i in 0..<operation_resolution_count(index) {
    guard operation_requirements_at(requirements, i).unwrap().requirement
      is @pipeline.AsOfRequirement(ResolveSearchWork) else {
      continue
    }
    found += 1
    let bounds = collect_asof_search_bounds(index, i, 10000000, 2).unwrap()
    assert_eq(asof_search_bound_candidate_count(bounds, 0), 1)
    assert_eq(asof_search_bound_candidate_count(bounds, 1), 0)
    assert_true(asof_search_bound_product(bounds) is None)
  }
  assert_eq(found, 1)
  assert_true(
    link_program_asof_search_limits(index, 10000000, 1, 2)
    is Err(MissingSearchBound),
  )
  assert_true(
    collect_asof_search_bounds(index, -1, 10000000, 2)
    is Err(InvalidRequirement),
  )
  assert_true(
    link_program_asof_search_limits(index, -1, 1, 2) is Err(InvalidLimits),
  )
  let other = join_resolution_fixture(interval_kind=Some("inner"))
  let unchanged = link_program_asof_search_limits(other, 10000000, 0, 0).unwrap()
  assert_eq(
    operation_resolution_unresolved_count(unchanged),
    operation_resolution_unresolved_count(other),
  )
}
