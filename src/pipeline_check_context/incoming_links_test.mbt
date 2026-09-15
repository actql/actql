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
  check_local_input_closure(linked)
  let input_requirement = incoming_links_local_input_at(linked, 0).unwrap()
  assert_true(input_requirement.snapshot is Some(_))
  assert_true(@local_input.primary_key(input_requirement.declaration) is None)
  assert_eq(local_input_execution_count(input_requirement), Some(1))
  let raw = local_input_execution_at(input_requirement, 0).unwrap()
  assert_true(physical_equal(raw.subject, input_requirement))
  assert_eq(raw.kind, RawBinding)
  assert_true(local_input_execution_predecessor(raw) is None)
  assert_true(local_input_execution_at(input_requirement, 1) is None)
  assert_true(physical_equal(incoming_links_profiles(linked), profiles))
  assert_true(physical_equal(incoming_links_requirements(linked), incoming))
  let (incoming_work, names) = program_incoming_usage(incoming)
  let resolutions = incoming_links_resolutions(linked)
  assert_true(
    physical_equal(operation_resolution_profiles(resolutions), profiles),
  )
  assert_true(
    physical_equal(operation_resolution_requirements(resolutions), requirements),
  )
  assert_true(operation_resolution_unresolved_count(resolutions) > 0)
  let expected = operation_resolution_work(resolutions) +
    incoming_work +
    1 +
    4 + // two stages, one local declaration and its one-unit name
    2 // one selected snapshot and its one-unit input name
  assert_eq(incoming_links_work(linked), expected)
  let exact : IncomingLimits = {
    max_work: expected,
    max_name_units: names,
    max_requirements: program_incoming_count(incoming),
  }
  assert_true(link_program_incoming(profiles, incoming, exact) is Ok(_))
  let retained = link_resolved_program_incoming(resolutions, incoming, exact).unwrap()
  assert_true(physical_equal(incoming_links_resolutions(retained), resolutions))
  assert_eq(incoming_links_work(retained), incoming_links_work(linked))
  assert_eq(
    incoming_links_local_input_count(retained),
    incoming_links_local_input_count(linked),
  )
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
    assert_true(
      link_resolved_program_incoming(resolutions, incoming, short)
      is Err(BudgetExceeded),
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
    assert_true(
      link_resolved_program_incoming(resolutions, incoming, invalid)
      is Err(InvalidLimits),
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
  assert_true(
    link_resolved_program_incoming(resolutions, foreign, generous)
    is Err(ForeignIdentity),
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

///|
test "incoming integration retains unexecuted top-tie checks from unused operations" {
  let requirements = operation_order_fixture(
    "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"dedupe_rows\":{\"by\":[],\"order_by\":[{\"id\":\"asc\"}]}}]",
  )
  let profiles = resolution_profiles(requirements)
  let identity = expression_closure_identity(
    operation_requirements_expressions(requirements),
  )
  let caps : IncomingLimits = {
    max_work: 10000000,
    max_name_units: 10000,
    max_requirements: 100,
  }
  let incoming = collect_program_incoming(identity, caps).unwrap()
  let linked = link_program_incoming(profiles, incoming, caps).unwrap()
  let index = incoming_links_resolutions(linked)
  let retained = link_resolved_program_incoming(index, incoming, caps).unwrap()
  assert_true(physical_equal(incoming_links_resolutions(retained), index))
  assert_true(
    physical_equal(operation_resolution_requirements(index), requirements),
  )
  assert_eq(operation_resolution_count(index), 3)
  for i in 0..<3 {
    guard operation_resolution_at(index, i)
      is Some(Execution(DedupeTopTie(check))) else {
      abort("missing owned execution requirement")
    }
    assert_true(
      physical_equal(
        check.site,
        operation_requirements_at(requirements, i).unwrap(),
      ),
    )
    assert_eq(check.site.step, 1)
  }
  // The old branch-only allowance cannot conceal the cost of building coverage.
  let prior = operation_profile_links_work(profiles) +
    program_incoming_usage(incoming).0 +
    1
  assert_true(
    link_program_incoming(profiles, incoming, { ..caps, max_work: prior, })
    is Err(BudgetExceeded),
  )
}
