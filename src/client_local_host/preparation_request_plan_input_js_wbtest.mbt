///|
test "Request Plan input retains the actual compiler across the real module and original Run" {
  let calls = Ref(0)
  let (parent, input, prepared) = request_program_body_fixture(current=() => {
    calls.val += 1
    true
  })
  let before = calls.val
  let holder = borrow_request_program_plan_input(parent, input).unwrap()
  assert_eq(calls.val - before, 1)
  let quote = parent.program_plan_quote.unwrap()
  assert_true(borrow_request_program_preparation(parent) is Err(WrongPhase))
  for _ in 0..<8 {
    assert_true(
      physical_equal(
        @resources.preparation_body_borrow_value(holder).unwrap(),
        prepared,
      ),
    )
  }
  assert_eq(calls.val - before, 1)
  assert_eq(parent.program_plan_quote.unwrap(), quote)
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  assert_eq(parent.program_plan_quote.unwrap(), quote)
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "plan-input-original",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.preparation_body_borrow_value(holder) is Some(_))
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request Effect Plan input remains distinct from its same original completed Plan body" {
  let (parent, input, prepared) = request_effect_compile_fixture()
  let holder = borrow_request_effect_plan_input(parent, input).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      prepared,
    ),
  )
  assert_true(borrow_request_effect_preparation(parent) is Err(WrongPhase))
  let (plan, request) = request_effect_plan_fixture(prepared)
  complete_request_effect_preparation(parent, input, plan).unwrap()
  let plan_holder = borrow_request_effect_preparation(parent).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(plan_holder).unwrap(),
      plan,
    ),
  )
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      prepared,
    ),
  )
  let run = begin_request_effect_managed_run(parent, request).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  assert_true(@resources.return_preparation_body_borrow(plan_holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request Plan input holds failed constructor DATA and charged debit until the exact return" {
  let (parent, input, prepared) = request_program_body_fixture()
  let holder = borrow_request_program_plan_input(parent, input).unwrap()
  assert_true(
    closed_module_test_catch(() => {
      ignore(
        prepare_request_program_module_body(
          parent,
          input,
          request_program_module_contracts(),
          manifests=request_program_module_manifests(),
          compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
          retained_output=true,
          provider_factory=_ => closed_module_test_throw(),
        ),
      )
    }),
  )
  assert_true(parent.phase == ProgramBodyFailed)
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_true(parent.phase == Retiring && parent.compiled_program is None)
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      prepared,
    ),
  )
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes > 0L,
  )
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(@resources.preparation_body_borrow_value(holder) is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request Plan input preserves later domain growth and the same cached quote without a foreign-input observation" {
  let calls = Ref(0)
  let (parent, input, prepared) = request_program_body_fixture(current=() => {
    calls.val += 1
    true
  })
  let holder = borrow_request_program_plan_input(parent, input).unwrap()
  let quote = parent.program_plan_quote.unwrap()
  let capacity = parent.program_capacity.unwrap()
  let (r, e) = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  @resources.reserve_working_preparation_phase(
    capacity,
    input,
    r + 17L,
    e + 19L,
  ).unwrap()
  let before = calls.val
  assert_true(
    borrow_request_program_plan_input(parent, [1]) is Err(ForeignOriginal),
  )
  assert_eq(calls.val, before)
  let second = borrow_request_program_plan_input(parent, input).unwrap()
  assert_eq(calls.val - before, 1)
  assert_eq(parent.program_plan_quote.unwrap(), quote)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((r + 17L, e + 19L)),
  )
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(second).unwrap(),
      prepared,
    ),
  )
  assert_false(@resources.return_preparation_body_borrow(second).unwrap())
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
