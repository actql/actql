///|
fn staged_closure_fixture(
  first_by_order? : Bool = false,
) -> ProgramIncomingLinks {
  let (identity, _, _) = prepared_identity_fixture(first_by_order~)
  let resolved = resolve_program_operations(identity, {
    max_work: 10000000,
    max_requirements: 100,
    max_resolutions: 100,
  }).unwrap()
  let limits : IncomingLimits = {
    max_work: 10000000,
    max_name_units: 10000,
    max_requirements: 100,
  }
  link_resolved_program_incoming(
    resolved,
    collect_program_incoming(identity, limits).unwrap(),
    limits,
  ).unwrap()
}

///|
test "staged requirement closure shares owners work and disposition limits" {
  let owner = staged_closure_fixture()
  let limits : StageRequirementLimits = {
    max_work: 10000000,
    max_requirements: 100,
    max_local_inputs: 1,
  }
  let closed = close_stage_requirements(owner, limits).unwrap()
  assert_true(physical_equal(stage_requirement_owner(closed), owner))
  let operations = stage_requirement_operations(closed)
  let inputs = stage_requirement_inputs(closed)
  let incoming = stage_requirement_incoming(closed)
  let publications = stage_requirement_publications(closed)
  assert_true(
    physical_equal(
      operation_closure_index(operations),
      incoming_links_resolutions(owner),
    ),
  )
  assert_true(physical_equal(local_input_closure_owner(inputs), owner))
  assert_true(physical_equal(incoming_closure_owner(incoming), owner))
  assert_true(physical_equal(publication_closure_owner(publications), owner))
  let (work, count) = stage_requirement_usage(closed)
  assert_eq(count, 8) // three Local checks, three activation checks, two Results
  let prefix = incoming_links_work(owner)
  assert_eq(
    work,
    prefix +
    1 +
    (
      operation_closure_work(operations) -
      operation_resolution_work(incoming_links_resolutions(owner))
    ) +
    (local_input_closure_work(inputs) - prefix) +
    (incoming_closure_work(incoming) - prefix) +
    (publication_closure_work(publications) - prefix) +
    (source_mode_closure_work(stage_requirement_source_modes(closed)) - prefix),
  )
  let exact = { ..limits, max_work: work, max_requirements: count, }
  assert_true(close_stage_requirements(owner, exact) is Ok(_))
  assert_true(
    close_stage_requirements(owner, { ..exact, max_work: work - 1, }) is Err(_),
  )
  assert_true(
    close_stage_requirements(owner, { ..exact, max_requirements: count - 1, })
    is Err(Publications(BudgetExceeded)),
  )
  assert_true(
    close_stage_requirements(owner, { ..exact, max_local_inputs: 0, })
    is Err(LocalInputs(BudgetExceeded)),
  )
  for
    invalid in [
      { ..exact, max_work: -1, },
      { ..exact, max_requirements: -1, },
      { ..exact, max_local_inputs: -1, },
    ] {
    assert_true(close_stage_requirements(owner, invalid) is Err(InvalidLimits))
  }
}

///|
test "staged closure cannot hide unresolved Local admission behind resolved operations" {
  let owner = staged_closure_fixture(first_by_order=true)
  assert_eq(
    operation_resolution_unresolved_count(incoming_links_resolutions(owner)),
    0,
  )
  assert_true(
    close_stage_requirements(owner, {
      max_work: 10000000,
      max_requirements: 100,
      max_local_inputs: 1,
    })
    is Err(LocalInputs(UnresolvedInput(0))),
  )
}
