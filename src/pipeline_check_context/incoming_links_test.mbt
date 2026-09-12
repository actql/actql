///|
test "incoming and operation branches require the same Program admission owner" {
  let profiles = profiles_from_ranges(
    query_fixture("{\"$param\":\"n\"}", "[1,2]"),
  )
  let calendar = operation_profile_links_calendar(profiles)
  let lexical = operation_calendar_lexical(calendar)
  let cells = operation_lexical_cells(lexical)
  let queries = operation_cells_queries(cells)
  let ranges = operation_queries_ranges(queries)
  let fills = operation_ranges_fills(ranges)
  let frames = operation_fills_frames(fills)
  let scalars = operation_frames_scalars(frames)
  let orders = operation_scalars_orders(scalars)
  let requirements = operation_orders_requirements(orders)
  let identity = expression_closure_identity(
    operation_requirements_expressions(requirements),
  )
  let generous : IncomingLimits = {
    max_work: 10000000,
    max_name_units: 10000,
    max_requirements: 100,
  }
  let incoming = collect_program_incoming(identity, generous).unwrap()
  let linked = link_program_incoming(profiles, incoming, generous).unwrap()
  assert_true(physical_equal(incoming_links_profiles(linked), profiles))
  assert_true(physical_equal(incoming_links_requirements(linked), incoming))
  let (incoming_work, names) = program_incoming_usage(incoming)
  let expected = operation_profile_links_work(profiles) +
    (incoming_work - program_identity_usage(identity).0) +
    1
  assert_eq(incoming_links_work(linked), expected)
  let exact : IncomingLimits = {
    max_work: expected,
    max_name_units: names,
    max_requirements: program_incoming_count(incoming),
  }
  assert_true(link_program_incoming(profiles, incoming, exact) is Ok(_))
  for
    short in [
      { ..exact, max_work: expected - 1, },
      { ..exact, max_name_units: names - 1, },
      { ..exact, max_requirements: exact.max_requirements - 1, },
      { ..exact, max_work: operation_profile_links_work(profiles), },
    ] {
    assert_true(
      link_program_incoming(profiles, incoming, short) is Err(BudgetExceeded),
    )
  }
  for
    invalid in [
      { ..exact, max_work: -1, },
      { ..exact, max_name_units: -1, },
      { ..exact, max_requirements: -1, },
    ] {
    assert_true(
      link_program_incoming(profiles, incoming, invalid) is Err(InvalidLimits),
    )
  }
  // Reissuing the identity from the very same source checks still creates a
  // distinct owner; equal Definition and values CIDs are insufficient.
  let reissued = identify_program_sources(
    program_identity_sources(identity),
    identity_limits(),
  ).unwrap()
  assert_eq(
    program_identity_definition_cid(reissued),
    program_identity_definition_cid(identity),
  )
  assert_eq(
    program_identity_parameter_values_cid(reissued),
    program_identity_parameter_values_cid(identity),
  )
  let foreign = collect_program_incoming(reissued, generous).unwrap()
  assert_true(
    link_program_incoming(profiles, foreign, generous) is Err(ForeignIdentity),
  )
  // A fresh incoming inventory from the exact owner remains admissible.
  assert_true(
    link_program_incoming(
      profiles,
      collect_program_incoming(identity, generous).unwrap(),
      exact,
    )
    is Ok(_),
  )
}
