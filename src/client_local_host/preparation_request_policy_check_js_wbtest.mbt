///|
test "Request policy supplement retains original Source Program Parameters Catalog and parent" {
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(
    environment,
    supplied=true,
  )
  let capacity = parent.capacity
  let old = parent.program_check.unwrap()
  let arguments = old.arguments.unwrap()
  let program = parent.held_program.unwrap()
  let parameters = parent.native_parameters.unwrap()
  let parameter_source = parent.parameter_source.unwrap()
  let before_subject = @checked.source_execution_subject(
    request_policy_checked_egress(parent),
  )
  assert_true(before_subject.request_value_policy is None)
  assert_true(
    before_subject.direct_policy.unwrap().classification is @environment.Unknown,
  )
  let evidence = [request_policy_supplement_evidence(parent)]
  let before = @resources.ledger_usage(parent.ledger)
  let selected = supplement_request_computation_policies(
    parent, input, environment, evidence,
  ).unwrap()
  let next = parent.program_check.unwrap()
  assert_false(physical_equal(selected, environment))
  assert_true(
    physical_equal(
      @checked.checking_environment_wire(selected),
      @checked.checking_environment_wire(environment),
    ),
  )
  assert_true(physical_equal(old, next))
  assert_true(next.phase == SemanticCheckComplete)
  assert_true(
    parent.phase == ProgramCheck && physical_equal(parent.capacity, capacity),
  )
  assert_true(physical_equal(parent.held_program.unwrap(), program))
  assert_true(physical_equal(parent.native_parameters.unwrap(), parameters))
  assert_true(
    physical_equal(parent.parameter_source.unwrap(), parameter_source),
  )
  assert_true(
    @checked.source_catalog_same_original(
      arguments.source_catalog.unwrap(),
      next.arguments.unwrap().source_catalog.unwrap(),
    ),
  )
  let after_subject = @checked.source_execution_subject(
    request_policy_checked_egress(parent),
  )
  assert_true(after_subject.request_value_policy is Some(_))
  assert_true(
    after_subject.direct_policy.unwrap().classification is @environment.Internal,
  )
  assert_true(parent.compiled_program is None && parent.compiled_effect is None)
  assert_true(parent.program_capacity is None && parent.effect_capacity is None)
  let after = @resources.ledger_usage(parent.ledger)
  assert_eq(before.live_reservations, after.live_reservations)
  assert_true(after.reserved_retention_bytes > before.reserved_retention_bytes)
  // Same completed evidence DATA neither rechecks nor consumes work again.
  assert_true(
    physical_equal(
      supplement_request_computation_policies(parent, input, selected, evidence).unwrap(),
      selected,
    ),
  )
  assert_true(physical_equal(parent.program_check.unwrap(), next))
  assert_eq(@resources.ledger_usage(parent.ledger), after)
  assert_true(
    supplement_request_computation_policies(
      parent, input, environment, evidence,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), after)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request policy supplement preserves full default versus supplied origin matching" {
  let environment = request_policy_supplement_environment()
  let (defaults, default_input) = request_policy_supplement_fixture(environment)
  let proof = request_policy_supplement_evidence(defaults)
  let (supplied, supplied_input) = request_policy_supplement_fixture(
    environment,
    supplied=true,
  )
  // Equal effective Parameter values do not exchange their original source.
  supplement_request_computation_policies(
    supplied,
    supplied_input,
    environment,
    [proof],
  ).unwrap()
  |> ignore
  let subject = @checked.source_execution_subject(
    request_policy_checked_egress(supplied),
  )
  assert_true(subject.request_value_policy is None)
  assert_true(
    subject.direct_policy.unwrap().classification is @environment.Unknown,
  )
  assert_true(supplied.compiled_program is None)
  abort_request_preparation_after_cleanup(supplied).unwrap()
  supplement_request_computation_policies(
    defaults,
    default_input,
    environment,
    [proof],
  ).unwrap()
  |> ignore
  let subject = @checked.source_execution_subject(
    request_policy_checked_egress(defaults),
  )
  assert_true(subject.request_value_policy is Some(_))
  assert_true(
    subject.direct_policy.unwrap().classification is @environment.Internal,
  )
  abort_request_preparation_after_cleanup(defaults).unwrap()
  assert_eq(@resources.ledger_usage(defaults.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(supplied.ledger).live_reservations, 0)
}

///|
test "Request policy supplement decline retains cleanup and cannot compile the old verdict" {
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(environment)
  let child = parent.program_check.unwrap()
  let proof = request_policy_supplement_evidence(parent)
  let before = @resources.ledger_usage(parent.ledger)
  let bytes = @execution.preparation_representation_cost(
      request_policy_selection_layout(1).unwrap(),
    ).unwrap() +
    program_check_data_extent_cost(child.check_data.unwrap()).unwrap()
  let limit = client_local_preparation_initial_limits(
      client_local_resource_policy(),
    ).unwrap().retained_bytes
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    limit - before.reserved_retention_bytes - bytes + 1L,
    0L,
  ).unwrap()
  assert_true(
    supplement_request_computation_policies(parent, input, environment, [proof])
    is Err(
      Preparation(
        Capacity(
          @resources.PreparationCapacityIssue::Resource(
            @resources.LedgerIssue::RetentionLimit
          )
        )
      )
    ),
  )
  assert_true(
    parent.phase == ProgramCheckFailed && child.phase == Failed && !child.busy,
  )
  assert_true(physical_equal(parent.program_check.unwrap(), child))
  assert_true(
    parent.compiled_program is None && parent.program_capacity is None,
  )
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  assert_true(
    finish_request_computation_preparation(parent, input)
    is Err(Preparation(WrongPhase)),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request policy supplement empty evidence and foreign input cannot refork its parent" {
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(environment)
  let child = parent.program_check.unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    supplement_request_computation_policies(parent, [1], environment, [])
    is Err(Preparation(ForeignOriginal)),
  )
  assert_true(
    physical_equal(
      supplement_request_computation_policies(parent, input, environment, []).unwrap(),
      environment,
    ),
  )
  assert_true(physical_equal(parent.program_check.unwrap(), child))
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request policy supplement retains original Effect headers and supplied Parameters" {
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(
    environment,
    supplied=true,
    effect=true,
  )
  let child = parent.program_check.unwrap()
  let before = child.effect_candidate.unwrap()
  let checked = @checked.effect_computation_checked_program(before)
  let headers = @checked.effect_computation_headers(before)
  let supplied = @checked.effect_computation_supplied(before).unwrap()
  let proof = request_policy_supplement_evidence(parent)
  supplement_request_computation_policies(parent, input, environment, [proof]).unwrap()
  |> ignore
  let selected = child.effect_candidate.unwrap()
  assert_true(
    physical_equal(@checked.effect_computation_headers(selected), headers),
  )
  assert_true(
    physical_equal(
      @checked.effect_computation_supplied(selected).unwrap(),
      supplied,
    ),
  )
  assert_true(
    physical_equal(
      @checked.source_identity(
        @checked.effect_computation_checked_program(selected),
      ),
      @checked.source_identity(checked),
    ),
  )
  assert_true(
    @checked.checked_program_has_effects(
      @checked.effect_computation_checked_program(selected),
    ),
  )
  let subject = @checked.source_execution_subject(
    request_policy_checked_egress(parent),
  )
  assert_true(
    subject.direct_policy.unwrap().classification is @environment.Internal,
  )
  assert_true(
    parent.compiled_effect is None &&
    child.compiled_effect is None &&
    parent.effect_capacity is None,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request policy supplement fences current reentry and selection input mutation" {
  for mutate in [false, true] {
    let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
    let armed = Ref(false)
    let calls = Ref(0)
    let fenced = Ref(0)
    let evidence : Array[@checked.HostRequestValuePolicyEvidence] = []
    let environment = request_policy_supplement_environment()
    let (parent, input) = request_policy_supplement_fixture(environment, current=() => {
      if armed.val {
        calls.val += 1
        let parent = selected.val.unwrap()
        if abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) &&
          supplement_request_computation_policies(
            parent,
            parent.input.unwrap(),
            environment,
            evidence,
          )
          is Err(Preparation(ForeignOriginal)) {
          fenced.val += 1
        }
        if mutate {
          evidence.clear()
        }
      }
      true
    })
    selected.val = Some(parent)
    let child = parent.program_check.unwrap()
    let original = request_policy_checked_program(parent)
    evidence.push(request_policy_supplement_evidence(parent))
    armed.val = true
    let result = supplement_request_computation_policies(
      parent, input, environment, evidence,
    )
    armed.val = false
    assert_true(calls.val > 0 && calls.val == fenced.val)
    assert_false(child.busy)
    if mutate {
      assert_true(result is Err(Preparation(ForeignOriginal)))
      assert_true(parent.phase == ProgramCheckFailed && child.phase == Failed)
      assert_true(
        physical_equal(request_policy_checked_program(parent), original),
      )
    } else {
      assert_true(result is Ok(_))
      assert_true(
        parent.phase == ProgramCheck && child.phase == SemanticCheckComplete,
      )
    }
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Request policy supplement retains cleanup after a foreign current throw" {
  let armed = Ref(false)
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(environment, current=() => {
    if armed.val {
      ignore(closed_module_test_throw())
    }
    true
  })
  let child = parent.program_check.unwrap()
  let proof = request_policy_supplement_evidence(parent)
  let before = request_policy_checked_program(parent)
  armed.val = true
  // The original Resource current port contains the foreign exception and
  // latches stopping; the original grow refuses ClosedReservation. No JS
  // exception or cleanup acknowledgement is supplied by that refusal.
  assert_true(
    supplement_request_computation_policies(parent, input, environment, [proof])
    is Err(
      Preparation(
        Capacity(
          @resources.PreparationCapacityIssue::Resource(
            @resources.ClosedReservation
          )
        )
      )
    ),
  )
  armed.val = false
  assert_true(
    parent.phase == ProgramCheckFailed && child.phase == Failed && !child.busy,
  )
  assert_true(physical_equal(request_policy_checked_program(parent), before))
  assert_true(
    parent.compiled_program is None && parent.program_capacity is None,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "policy continuation generic Result scope finalizes once before foreign throw escapes" {
  let finalized = Ref(0)
  assert_true(
    closed_module_test_catch(() => {
      let result : Result[@checked.CheckEnvironment, ClientRequestTerminalIssue] = preparation_module_call(
        () => {
          ignore(closed_module_test_throw())
          Err(Preparation(WrongPhase))
        },
        () => finalized.val += 1,
      )
      ignore(result)
    }),
  )
  assert_eq(finalized.val, 1)
}
