///|
test "interval search closes both resources with owned sparse candidates and one shared product" {
  for host_first in [false, true] {
    for kind in ["inner", "left", "semi", "anti"] {
      let index = join_resolution_fixture(host_first~, interval_kind=Some(kind))
      let requirements = operation_resolution_requirements(index)
      let count = operation_resolution_count(index)
      let linked = link_program_interval_search_limits(index, 10000000, 2, 2).unwrap()
      assert_eq(
        operation_resolution_unresolved_count(linked),
        operation_resolution_unresolved_count(index) - 2,
      )
      let mut seen = 0
      let mut product_site = -1
      for i in 0..<count {
        let site = operation_requirements_at(requirements, i).unwrap()
        guard operation_resolution_at(linked, i)
          is Some(Execution(IntervalSearch(check))) else {
          continue
        }
        seen += 1
        assert_true(physical_equal(check.site, site))
        assert_true(
          physical_equal(interval_search_bound_owner(check.bounds), index),
        )
        assert_true(
          physical_equal(
            interval_search_bound_product(check.bounds).unwrap(),
            check.product,
          ),
        )
        assert_eq(@program.interval_search_upper(check.product), 1L)
        assert_eq(
          operation_execution_phase(IntervalSearch(check)),
          BeforeOperationInputUse,
        )
        assert_eq(
          operation_execution_failure(IntervalSearch(check)),
          RejectOperationOutput,
        )
        if check.rule == CheckOperandProduct {
          product_site = i
        }
        for side in 0..<2 {
          assert_eq(
            interval_search_bound_candidate_count(check.bounds, side),
            1,
          )
          let membership = interval_search_bound_candidate_at(
            check.bounds,
            side,
            0,
          ).unwrap()
          assert_true(
            physical_equal(
              @capacity.target_membership_closure(membership),
              interval_search_bound_closure(check.bounds),
            ),
          )
          let rows = @capacity.target_membership_rows(membership)
          assert_true(
            physical_equal(
              @program.interval_search_bound_at(check.product, side).unwrap(),
              rows,
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
            interval_search_bound_candidate_at(check.bounds, side, 1) is None,
          )
        }
        assert_true(
          interval_search_bound_candidate_at(check.bounds, -1, 0) is None,
        )
        assert_true(operation_resolution_at(index, i) is Some(Unresolved))
      }
      assert_eq(seen, 2)
      assert_true(product_site >= 0)
      let bounds = collect_interval_search_bounds(
        index, product_site, 10000000, 2,
      ).unwrap()
      let used = interval_search_bound_work(bounds)
      assert_true(
        collect_interval_search_bounds(index, product_site, used, 2) is Ok(_),
      )
      assert_true(
        collect_interval_search_bounds(index, product_site, used - 1, 2)
        is Err(BudgetExceeded),
      )
      assert_true(
        collect_interval_search_bounds(index, product_site, used, 1)
        is Err(BudgetExceeded),
      )
      let work = operation_resolution_work(linked)
      assert_true(
        link_program_interval_search_limits(index, work, 2, 2) is Ok(_),
      )
      assert_true(
        link_program_interval_search_limits(index, work - 1, 2, 2)
        is Err(BudgetExceeded),
      )
      assert_true(
        link_program_interval_search_limits(index, work, 1, 2)
        is Err(BudgetExceeded),
      )
      assert_true(
        link_program_interval_search_limits(index, work, 2, 1)
        is Err(BudgetExceeded),
      )
      assert_true(
        link_program_interval_search_limits(linked, 10000000, 2, 2)
        is Err(ForeignEvidence),
      )
      // Output enforcement is separate and remains linkable, never consumed as search evidence.
      let with_output = link_program_join_requirements(linked, 10000000, 4).unwrap()
      let mut interval_checks = 0
      for j in 0..<count {
        if operation_requirements_at(requirements, j).unwrap().requirement
          is @pipeline.IntervalJoinRequirement(_) {
          interval_checks += 1
          assert_true(
            operation_resolution_at(with_output, j) is Some(Execution(_)),
          )
        }
      }
      // Endpoint/clock admission, occurrence order, product, search and output
      // remain distinct, but all six now have owned future execution checks.
      assert_eq(interval_checks, 6)
    }
  }
}

///|
test "interval search cannot replace missing operand evidence with a Host output ceiling" {
  let index = join_resolution_fixture(
    host_first=true,
    interval_kind=Some("semi"),
    interval_with="joined",
  )
  let requirements = operation_resolution_requirements(index)
  let mut found = 0
  for i in 0..<operation_resolution_count(index) {
    guard operation_requirements_at(requirements, i).unwrap().requirement
      is @pipeline.IntervalJoinRequirement(ResolveProductBound) else {
      continue
    }
    found += 1
    let bounds = collect_interval_search_bounds(index, i, 10000000, 2).unwrap()
    assert_eq(interval_search_bound_candidate_count(bounds, 0), 1)
    assert_eq(interval_search_bound_candidate_count(bounds, 1), 0)
    assert_true(interval_search_bound_product(bounds) is None)
    let used = interval_search_bound_work(bounds)
    assert_true(
      collect_interval_search_bounds(index, i, used - 1, 2)
      is Err(BudgetExceeded),
    )
  }
  assert_eq(found, 1)
  assert_true(
    link_program_interval_search_limits(index, 10000000, 2, 2)
    is Err(MissingSearchBound),
  )
  assert_true(
    collect_interval_search_bounds(index, -1, 10000000, 2)
    is Err(InvalidRequirement),
  )
  assert_true(
    link_program_interval_search_limits(index, -1, 2, 2) is Err(InvalidLimits),
  )
}
