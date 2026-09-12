///|
fn core_profile_identity(
  cells : ProgramOperationCells,
) -> ProgramSourceIdentity {
  let requirements = operation_orders_requirements(
    operation_scalars_orders(
      operation_frames_scalars(
        operation_fills_frames(
          operation_ranges_fills(
            operation_queries_ranges(operation_cells_queries(cells)),
          ),
        ),
      ),
    ),
  )
  expression_closure_identity(operation_requirements_expressions(requirements))
}

///|
test "TextRank contract collection requires the owned resolved data profile" {
  let cells = lexical_cells(lexical_host(), true)
  let identity = core_profile_identity(cells)
  let limits : CoreContractLimits = {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }
  assert_true(
    collect_core_contracts(identity, limits)
    is Err(UnresolvedProfileData(_, _, 2, @pipeline.TextRankProfile)),
  )
  let selected = lexical_artifact(cells)
  let lexical = check_program_operation_lexical(
    cells,
    Some(selected),
    10000000,
    100,
  ).unwrap()
  let profiles = check_program_operation_calendar(lexical, None, 10000000, 100).unwrap()
  let inventory = collect_core_contracts(
    identity,
    limits,
    profile_checks=Some(profiles),
  ).unwrap()
  assert_true(
    physical_equal(core_contract_profile_checks(inventory).unwrap(), profiles),
  )
  let mut occurrences = 0
  for i in 0..<core_contract_root_count(inventory) {
    let root = core_contract_root_at(inventory, i).unwrap()
    if root.site is OperationDataProfile(stage, visit, step, profile) {
      assert_eq(profile, @pipeline.TextRankProfile)
      assert_eq(root.body, TextRankProfileData(text_profile_fixture_cid()))
      guard @pipeline.step_at(
          program_identity_producer_at(identity, stage, visit).unwrap(),
          step,
        ).unwrap().operation
        is @pipeline.TextRank(checked=op, ..) else {
        abort("profile root owner")
      }
      assert_true(@vector.text_rank_profile(op) is None)
      occurrences += 1
    }
  }
  assert_eq(occurrences, operation_lexical_count(lexical))
  assert_true(occurrences > 1)
  let exact : CoreContractLimits = {
    max_work: core_contract_usage(inventory).0,
    max_roots: core_contract_root_count(inventory),
    max_bodies: core_contract_body_count(inventory),
    max_edges: core_contract_usage(inventory).1,
  }
  assert_true(
    collect_core_contracts(identity, exact, profile_checks=Some(profiles))
    is Ok(_),
  )
  for
    l in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_roots: exact.max_roots - 1, },
      { ..exact, max_bodies: exact.max_bodies - 1, },
      { ..exact, max_edges: exact.max_edges - 1, },
    ] {
    assert_true(
      collect_core_contracts(identity, l, profile_checks=Some(profiles))
      is Err(_),
    )
  }
  let other = core_profile_identity(lexical_cells(lexical_host(), true))
  assert_eq(
    program_identity_definition_cid(other),
    program_identity_definition_cid(identity),
  )
  assert_true(
    collect_core_contracts(other, limits, profile_checks=Some(profiles))
    is Err(ForeignProfiles),
  )
}

///|
test "Calendar contract roots retain the checked table at each operation" {
  let lexical = calendar_program(program_calendar_host())
  let identity = core_profile_identity(operation_lexical_cells(lexical))
  let profiles = check_program_operation_calendar(
    lexical,
    Some(program_calendar_artifact(lexical)),
    10000000,
    100,
  ).unwrap()
  let inventory = collect_core_contracts(
    identity,
    { max_work: 10000000, max_roots: 1000, max_bodies: 100, max_edges: 100, },
    profile_checks=Some(profiles),
  ).unwrap()
  let mut occurrences = 0
  let mut tables = 0
  for i in 0..<core_contract_root_count(inventory) {
    let root = core_contract_root_at(inventory, i).unwrap()
    if root.site is OperationDataProfile(stage, visit, step, profile) {
      assert_eq(profile, @pipeline.CalendarProfile)
      guard @pipeline.step_at(
          program_identity_producer_at(identity, stage, visit).unwrap(),
          step,
        ).unwrap().operation
        is @pipeline.Calendar(op) else {
        abort("Calendar root owner")
      }
      assert_eq(
        root.body,
        CalendarProfileData(@calendar_profile.cid(@calendar.profile(op))),
      )
      assert_eq(
        core_contract_cid(root.body),
        "sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca",
      )
      occurrences += 1
    }
  }
  for i in 0..<core_contract_body_count(inventory) {
    if core_contract_body_at(inventory, i) is Some(CalendarProfileData(_)) {
      tables += 1
    }
  }
  assert_true(occurrences > 1)
  assert_eq(tables, 1)
}
