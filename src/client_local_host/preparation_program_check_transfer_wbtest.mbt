///|
// Real original Core preparation/reader DATA. These fixture teardown calls
// supply no backend backing, ordinary Host or physical-cleanup observation.
test "Check clear retains actual parsed-input handoff fact" {
  let (owner, ledger, capacity, input) = catalog_domain_fixture()
  let program = owner.arguments.unwrap().program
  prepare_program_check_input(owner).unwrap()
  let before = @resources.ledger_usage(ledger)
  {
    let original = take_program_check_input(owner).unwrap()
    let work = @checked.parsed_check_input_binding_work(original)
    clear_program_check_preparation(owner).unwrap()
    clear_program_check_preparation(owner).unwrap()
    assert_true(owner.phase == Transferred)
    assert_true(physical_equal(original.program, program))
    assert_eq(@checked.parsed_check_input_binding_work(original), work)
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_true(take_program_check_input(owner) is Err(WrongPhase))
  }
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
}

///|
test "Check clear retains actual Catalog handoff fact" {
  let (owner, ledger, capacity, input) = catalog_domain_fixture()
  prepare_program_check_input(owner).unwrap()
  prepare_program_check_prelude(owner).unwrap() |> ignore
  let prepared = prepare_program_check_registry(owner).unwrap()
  let before = @resources.ledger_usage(ledger)
  {
    let original = take_program_check_registry(owner).unwrap()
    clear_program_check_preparation(owner).unwrap()
    clear_program_check_preparation(owner).unwrap()
    assert_true(owner.phase == Transferred)
    assert_true(physical_equal(original, prepared))
    assert_true(
      @checked.parsed_check_registry_remaining_work(original) is Ok(_),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_true(take_program_check_registry(owner) is Err(WrongPhase))
  }
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
}

///|
test "Check clear untransferred controls keep typed constructor refusal retired" {
  let (owner, ledger, capacity, input) = catalog_domain_fixture()
  // The explicit Core fixture selects this compile-work limit before any
  // reader. It never changes the Program or marks an output as transferred.
  let original = owner.arguments.unwrap()
  owner.arguments = Some({
    ..original,
    limits: {
      ..original.limits,
      compilation: { ..original.limits.compilation, work: 11, },
    },
  })
  assert_true(
    prepare_program_check_input(owner)
    is Err(Check(CapacityInputs(BudgetExceeded))),
  )
  assert_true(owner.phase == Failed && owner.work is None)
  let before = @resources.ledger_usage(ledger)
  clear_program_check_preparation(owner).unwrap()
  clear_program_check_preparation(owner).unwrap()
  assert_true(owner.phase == Retired)
  assert_true(owner.arguments is None && owner.check_input is None)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(take_program_check_input(owner) is Err(WrongPhase))
  assert_true(
    @resources.begin_preparation_phase_work64(
      capacity,
      input,
      @resources.CapacityInputInspection,
      1L,
    )
    is Err(AlreadyClaimed),
  )
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
}

///|
test "Check clear untransferred controls keep one-short original growth retired" {
  for retention in [true, false] {
    let (owner, ledger, capacity, input) = catalog_domain_fixture()
    let required_r = owner.base_retained + 47960L + 9888L
    let required_e = owner.base_execution + 47960L + 9888L
    let limits = @resources.ledger_limits(ledger)
    let blocker = @resources.reserve_capacity(
      ledger,
      if retention {
        limits.retained_bytes - required_r + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - required_e + 1L
      },
    ).unwrap()
    let failed = prepare_program_check_input(owner)
    assert_true(
      if retention {
        failed is Err(Capacity(Resource(RetentionLimit)))
      } else {
        failed is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(owner.phase == BindingQuoted && owner.work is None)
    let before = @resources.ledger_usage(ledger)
    clear_program_check_preparation(owner).unwrap()
    clear_program_check_preparation(owner).unwrap()
    assert_true(owner.phase == Retired)
    assert_true(owner.arguments is None && owner.binding_quote is None)
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_true(take_program_check_registry(owner) is Err(WrongPhase))
    @resources.settle_capacity(ledger, blocker).unwrap()
    assert_true(
      @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
    )
  }
}
