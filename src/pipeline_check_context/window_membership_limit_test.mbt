///|
test "window limits select the Carrier Host scope without discarding Program candidates" {
  for events in [false, true] {
    let index = join_resolution_fixture(
      host_first=true,
      window_events=events,
      temporal_rows=7,
      window_body=Some(
        (if events { "" } else { "\"time\":\"id\"," }) +
        "\"kind\":\"sliding\",\"size\":10,\"step\":3",
      ),
    )
    let linked = link_program_window_membership_limits(index, 10000000, 1, 2).unwrap()
    let mut found = 0
    for i in 0..<operation_resolution_count(linked) {
      guard operation_resolution_at(linked, i)
        is Some(Execution(WindowMembershipLimit(limit))) else {
        continue
      }
      found += 1
      assert_true(
        physical_equal(
          limit.site,
          operation_requirements_at(operation_resolution_requirements(index), i).unwrap(),
        ),
      )
      assert_true(
        physical_equal(window_membership_bound_owner(limit.bounds), index),
      )
      assert_eq(window_membership_bound_requirement(limit.bounds), i)
      assert_eq(
        @policy.ceiling_field(limit.host),
        if events {
          "max_temporal_output_rows"
        } else {
          "max_relation_output_rows"
        },
      )
      assert_eq(@policy.ceiling_value(limit.host), if events { 7L } else { 1L })
      assert_eq(limit.maximum, if events { 4L } else { 1L })
      assert_eq(window_membership_bound_maximum(limit.bounds), Some(4L))
      assert_eq(window_membership_bound_candidate_count(limit.bounds), 1)
      assert_true(operation_resolution_at(index, i) is Some(Unresolved))
      assert_eq(
        operation_execution_phase(WindowMembershipLimit(limit)),
        BeforeOperationOutput,
      )
      assert_eq(
        operation_execution_failure(WindowMembershipLimit(limit)),
        RejectOperationOutput,
      )
    }
    assert_eq(found, 1)
    assert_eq(
      operation_resolution_unresolved_count(linked),
      operation_resolution_unresolved_count(index) - 1,
    )
    let work = operation_resolution_work(linked)
    assert_true(
      link_program_window_membership_limits(index, work, 1, 2) is Ok(_),
    )
    assert_true(
      link_program_window_membership_limits(index, work - 1, 1, 2)
      is Err(BudgetExceeded),
    )
    assert_true(
      link_program_window_membership_limits(index, 10000000, 0, 2)
      is Err(BudgetExceeded),
    )
    assert_true(
      link_program_window_membership_limits(index, 10000000, 1, 1)
      is Err(BudgetExceeded),
    )
    assert_true(
      link_program_window_membership_limits(linked, 10000000, 1, 2)
      is Err(ForeignEvidence),
    )
    assert_true(
      close_program_operations(linked, 10000000, 1000)
      is Err(IncompleteResolution(_)),
    )
  }
}

///|
test "window output Host enforcement does not invent an input bound" {
  let index = index_program_operation_resolutions(
    resolution_profiles(
      operation_order_fixture(
        scalar_steps(
          "{\"row_window\":{\"time\":\"id\",\"kind\":\"fixed\",\"size\":10}}",
        ),
        tea=true,
      ),
    ),
    10000000,
    1000,
  ).unwrap()
  let linked = link_program_window_membership_limits(index, 10000000, 3, 3).unwrap()
  let mut found = 0
  for i in 0..<operation_resolution_count(linked) {
    guard operation_resolution_at(linked, i)
      is Some(Execution(WindowMembershipLimit(limit))) else {
      continue
    }
    found += 1
    assert_eq(window_membership_bound_maximum(limit.bounds), None)
    assert_eq(window_membership_bound_candidate_count(limit.bounds), 0)
    assert_eq(limit.maximum, @policy.ceiling_value(limit.host))
  }
  assert_eq(found, 3)
}
