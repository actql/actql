///|
test "normal Request terminal selects the original Pure inventory and consumes checker compiler once" {
  let limits = @publication_host.client_standard_program_preparation_limits()
  let (parent, child, _, input) = registration_parent_fixture(
    computation_limits=Some(
      (limits, @publication_host.client_standard_effect_computation_limits()),
    ),
  )
  let program = parent.held_program.unwrap()
  let registry = child.check_registry.unwrap()
  assert_eq(@syntax.program_preparation_data(program).effect_members, 0)
  assert_true(child.effect_limits is None)
  assert_true(physical_equal(parent.computation_limits.unwrap(), limits))
  finish_request_computation_preparation(parent, input).unwrap()
  assert_true(
    parent.phase == ProgramCompiled && parent.compiled_program is Some(_),
  )
  assert_true(
    parent.program_capacity is Some(_) && parent.effect_capacity is None,
  )
  assert_true(child.phase == Transferred && parent.program_check is None)
  assert_true(
    @checked.parsed_check_registry_remaining_work(registry)
    is Err(AlreadyConsumed),
  )
  let usage = @resources.ledger_usage(parent.ledger)
  assert_true(
    finish_request_computation_preparation(parent, input)
    is Err(Preparation(WrongPhase)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), usage)
  // Prepared remains private to this same working parent until funded Plan/borrow.
  let prepared = parent.compiled_program.unwrap()
  reserve_request_program_plan(parent, input).unwrap()
  complete_request_program_preparation(
    parent,
    input,
    request_program_installed_plan(prepared),
  ).unwrap()
  let holder = borrow_request_program_preparation(parent).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      prepared,
    ),
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "normal Request terminal selects the original Effect inventory Parameters and typed continuation" {
  let (parent, child, input, supplied) = request_effect_fixture(automatic=true)
  let program = parent.held_program.unwrap()
  assert_eq(@syntax.program_preparation_data(program).effect_members, 1)
  assert_true(child.effect_limits is Some(_))
  assert_true(
    physical_equal(child.arguments.unwrap().supplied.unwrap(), supplied),
  )
  finish_request_computation_preparation(parent, input).unwrap()
  assert_true(
    parent.phase == EffectCompiled && parent.compiled_effect is Some(_),
  )
  assert_true(
    parent.effect_capacity is Some(_) && parent.program_capacity is None,
  )
  assert_true(child.phase == Transferred && parent.program_check is None)
  let usage = @resources.ledger_usage(parent.ledger)
  assert_true(
    finish_request_computation_preparation(parent, input)
    is Err(Preparation(WrongPhase)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), usage)
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "normal Request terminal retains the actual typed rejection without compiler or fallback" {
  let text = request_check_wire.replace(old="\"take\":1", new="\"take\":-1")
  let (parent, child, _, input) = registration_parent_fixture(
    text~,
    computation_limits=Some(
      (
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
      ),
    ),
  )
  let result = finish_request_computation_preparation(parent, input)
  guard result is Err(CheckOutcome(@checked.Rejected(original))) else {
    fail("Original negative Take rejection must survive terminal handoff")
  }
  guard child.check_outcome is Some(@checked.Rejected(retained)) else {
    fail("Original checker must retain the same rejection")
  }
  assert_true(physical_equal(original, retained))
  assert_true(parent.compiled_program is None && parent.compiled_effect is None)
  assert_true(child.compiled_program is None && child.compiled_effect is None)
  assert_true(child.phase == SemanticCheckRejected)
  let before = @resources.ledger_usage(parent.ledger)
  guard finish_request_computation_preparation(parent, input)
    is Err(CheckOutcome(@checked.Rejected(same))) else {
    fail(
      "Reading retained rejection must not become WrongPhase or repeat check",
    )
  }
  assert_true(physical_equal(original, same))
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.computation_limits is None)
}
