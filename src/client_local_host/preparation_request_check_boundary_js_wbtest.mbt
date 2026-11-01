///|
test "Request check boundary retains native Program Parameters and Unit reservation before compiler" {
  let (environment, publication) = request_query_publication_fixture()
  let limits = @publication_host.client_standard_program_preparation_limits()
  let (parent, input) = native_driver_parent(native_driver_program)
  let capacity = parent.capacity
  let source = prepare_request_native_program_input(
    parent,
    input,
    request_native_test_value(native_driver_program),
    native_json_reader,
    limits.checking.input,
    supplied=Some(request_native_test_value("{\"n\":9}")),
  ).unwrap()
  construct_program_json_preparation(source).unwrap() |> ignore
  reconcile_program_json_preparation_structure(source).unwrap() |> ignore
  let parameters = parent.native_parameters.unwrap()
  prepare_request_original_computation_check(
    parent,
    input,
    environment,
    publication,
    [],
    limits,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let child = parent.program_check.unwrap()
  let program = parent.held_program.unwrap()
  let registry = child.check_registry.unwrap()
  assert_true(parent.phase == ProgramCheck)
  assert_true(child.phase == SemanticCheckComplete)
  assert_true(child.check_outcome is Some(@checked.Checked(_)))
  assert_true(parent.program_capacity is None && parent.effect_capacity is None)
  assert_true(parent.compiled_program is None && parent.compiled_effect is None)
  assert_true(child.compiled_program is None && child.compiled_effect is None)
  assert_true(
    parent.program_source_free is None && parent.program_captured is None,
  )
  assert_true(physical_equal(parent.capacity, capacity))
  assert_true(physical_equal(parent.native_parameters.unwrap(), parameters))
  let checked_usage = @resources.ledger_usage(parent.ledger)
  finish_request_computation_check(parent, input).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger), checked_usage)
  assert_true(physical_equal(parent.held_program.unwrap(), program))
  assert_true(
    @checked.parsed_check_registry_remaining_work(registry)
    is Err(AlreadyConsumed),
  )
  // No compiler/body is selected merely by keeping the checked Request live.
  // The existing final continuation consumes that same checker exactly once.
  finish_request_computation_preparation(parent, input).unwrap()
  assert_true(parent.phase == ProgramCompiled)
  assert_true(
    parent.compiled_program is Some(_) && parent.compiled_effect is None,
  )
  assert_true(
    parent.program_capacity is Some(_) && parent.effect_capacity is None,
  )
  assert_true(child.phase == Transferred && parent.program_check is None)
  assert_true(physical_equal(parent.held_program.unwrap(), program))
  assert_true(physical_equal(parent.native_parameters.unwrap(), parameters))
  assert_eq(
    @resources.ledger_usage(parent.ledger).live_reservations,
    checked_usage.live_reservations,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request check boundary retains original Effect candidate before typed compiler selection" {
  let (parent, child, input, supplied) = request_effect_fixture(automatic=true)
  let capacity = parent.capacity
  finish_request_computation_check(parent, input).unwrap()
  assert_true(
    parent.phase == ProgramCheck && child.phase == SemanticCheckComplete,
  )
  assert_true(child.effect_candidate is Some(_))
  assert_true(child.compiled_program is None && child.compiled_effect is None)
  assert_true(parent.program_capacity is None && parent.effect_capacity is None)
  assert_true(physical_equal(parent.capacity, capacity))
  assert_true(
    physical_equal(child.arguments.unwrap().supplied.unwrap(), supplied),
  )
  let checked_usage = @resources.ledger_usage(parent.ledger)
  finish_request_computation_check(parent, input).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger), checked_usage)
  finish_request_computation_preparation(parent, input).unwrap()
  assert_true(
    parent.phase == EffectCompiled && parent.compiled_effect is Some(_),
  )
  assert_true(
    parent.program_capacity is None && parent.effect_capacity is Some(_),
  )
  assert_true(child.phase == Transferred)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request check boundary rejects foreign input and closes without a compiler or body" {
  let limits = @publication_host.client_standard_program_preparation_limits()
  let (parent, child, _, input) = registration_parent_fixture(
    computation_limits=Some(
      (limits, @publication_host.client_standard_effect_computation_limits()),
    ),
  )
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    finish_request_computation_check(parent, [1])
    is Err(Preparation(WrongPhase)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  finish_request_computation_check(parent, input).unwrap()
  assert_true(
    child.phase == SemanticCheckComplete && parent.phase == ProgramCheck,
  )
  assert_true(parent.compiled_program is None && parent.compiled_effect is None)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.phase == Closed && child.phase == Retired)
  assert_true(
    finish_request_computation_preparation(parent, input)
    is Err(Preparation(WrongPhase)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
