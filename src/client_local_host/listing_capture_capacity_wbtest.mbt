///|
test "listing capture planner adds exact report amounts to the same original requirement" {
  let acquisition = listing_report_acquisition_fixture()
  let original = installed_row_capture_capacity(acquisition).unwrap()
  let report = @execution.execution_capacity(7L, 9L).unwrap()
  let complete = installed_listing_row_capture_capacity(
    acquisition,
    Some(report),
  ).unwrap()
  assert_eq(complete.retained_bytes, original.retained_bytes + 7L + 40L)
  assert_eq(complete.execution_bytes, original.execution_bytes + 9L + 40L)
  assert_true(physical_equal(complete.requirement, original.requirement))
  assert_eq(complete.original_input, original.original_input)
  // Independently counted original configuration binding: H1/R2/W1 = 40.
  assert_true(
    installed_provider_row_capture_capacity_matches(
      complete, acquisition, report,
    ),
  )
  let equal_report = @execution.execution_capacity(7L, 9L).unwrap()
  assert_false(
    installed_provider_row_capture_capacity_matches(
      complete, acquisition, equal_report,
    ),
  )
  // Small units prove DATA addition/binding only, not a numerical profile.
}

///|
test "listing planner refuses unavailable zero and overflowing supplementary declarations" {
  let acquisition = listing_report_acquisition_fixture()
  assert_true(installed_listing_row_capture_capacity(acquisition, None) is None)
  assert_true(
    installed_listing_row_capture_capacity(
      acquisition,
      @execution.execution_capacity(0L, 0L),
    )
    is None,
  )
  assert_true(
    installed_listing_row_capture_capacity(
      acquisition,
      @execution.execution_capacity(9223372036854775807L, 9223372036854775807L),
    )
    is None,
  )
}

///|
test "listing capture declaration cannot change an ordinary row acquisition" {
  let (prepared, _, _, _) = original_prefix_execution_fixture(source=true)
  let acquisition = original_row_acquisition_fixture(
    original_row_requirement(prepared),
  )
  assert_false(@row_source_host.row_acquisition_is_listing(acquisition))
  assert_true(
    installed_listing_row_capture_capacity(
      acquisition,
      @execution.execution_capacity(7L, 9L),
    )
    is None,
  )
  assert_true(installed_row_capture_capacity(acquisition) is Some(_))
}
