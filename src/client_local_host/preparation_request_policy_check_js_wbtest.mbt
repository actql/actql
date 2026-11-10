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
      closed_values_program_arrays(1L, 1L, false),
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

///|
fn funded_policy_subjects_test_limits() -> @checked.CompileLimits {
  {
    ..@publication_host.client_standard_program_preparation_limits().checking.compilation,
    work: 1000000,
    artifacts: { bytes: 1000000, nodes: 100000, depth: 100, },
  }
}

///|
fn funded_policy_subjects_prepare(
  parent : ClientRequestPreparation[Array[Int]],
  input : Array[Int],
  environment : @checked.CheckEnvironment,
) -> Result[Int, ClientRequestTerminalIssue] {
  prepare_request_computation_policy_subjects(
    parent,
    input,
    environment,
    funded_policy_subjects_test_limits(),
  )
}

///|
test "funded policy subjects keep original work through verifier binding and compiler" {
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(
    environment,
    supplied=true,
  )
  let child = parent.program_check.unwrap()
  let capacity = parent.capacity
  let parameters = parent.native_parameters.unwrap()
  let program = parent.held_program.unwrap()
  assert_eq(
    funded_policy_subjects_prepare(parent, input, environment).unwrap(),
    1,
  )
  let subjects = child.policy_subjects.unwrap()
  let work = child.policy_subject_work.unwrap()
  let wire = request_computation_policy_subject(parent, input, environment, 0).unwrap()
  assert_true(wire.contains("\"origin\":\"supplied\",\"parameter\":\"key\""))
  let before = @resources.ledger_usage(parent.ledger)
  let spent = @checked.request_policy_subjects_spent_work(subjects)
  assert_eq(
    request_computation_policy_subject(parent, input, environment, 0).unwrap(),
    wire,
  )
  assert_eq(@checked.request_policy_subjects_spent_work(subjects), spent)
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(
    finish_request_computation_preparation(parent, input)
    is Err(Preparation(WrongPhase)),
  )
  assert_true(
    funded_policy_subjects_prepare(parent, input, environment)
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  bind_request_computation_policy_subject(
    parent,
    input,
    environment,
    0,
    Some(
      "sha256:bc75d87043cc6314215460b4e0f2fbf5a72363edbe989ee7bb69acfc9021c808",
    ),
  ).unwrap()
  assert_true(physical_equal(child.policy_subject_work.unwrap(), work))
  assert_true(@checked.request_policy_subjects_spent_work(subjects) > spent)
  finish_request_computation_policy_subjects(parent, input, environment).unwrap()
  assert_true(
    child.policy_subject_work is None && child.policy_subjects is None,
  )
  assert_true(
    @checked.source_execution_subject(request_policy_checked_egress(parent)).request_value_policy
    is Some(_),
  )
  finish_request_computation_preparation(parent, input).unwrap()
  assert_true(parent.compiled_program is Some(_))
  assert_true(physical_equal(parent.capacity, capacity))
  assert_true(physical_equal(parent.native_parameters.unwrap(), parameters))
  assert_true(physical_equal(parent.held_program.unwrap(), program))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "funded policy subjects consume explicit declines and cannot finalize missing verifier entries" {
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(environment)
  funded_policy_subjects_prepare(parent, input, environment).unwrap() |> ignore
  let child = parent.program_check.unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    finish_request_computation_policy_subjects(parent, input, environment)
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(
    request_computation_policy_subject(parent, [1], environment, 0)
    is Err(Preparation(ForeignOriginal)),
  )
  bind_request_computation_policy_subject(parent, input, environment, 0, None).unwrap()
  finish_request_computation_policy_subjects(parent, input, environment).unwrap()
  assert_true(
    child.policy_subject_work is None && child.policy_subjects is None,
  )
  assert_true(
    @checked.source_execution_subject(request_policy_checked_egress(parent)).request_value_policy
    is None,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "funded policy subjects refuse a foreign policy without recompiling or refunding their work" {
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(environment)
  funded_policy_subjects_prepare(parent, input, environment).unwrap() |> ignore
  let child = parent.program_check.unwrap()
  let work = child.policy_subject_work.unwrap()
  assert_true(
    bind_request_computation_policy_subject(
      parent,
      input,
      environment,
      0,
      Some("sha256:" + "0".repeat(64)),
    )
    is Err(Preparation(ProgramCheck(RequestPolicySubjects(_)))),
  )
  assert_true(
    child.phase == Failed && !child.busy && parent.phase == ProgramCheckFailed,
  )
  assert_true(physical_equal(child.policy_subject_work.unwrap(), work))
  assert_true(
    finish_request_computation_preparation(parent, input)
    is Err(Preparation(WrongPhase)),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "funded policy subjects retire a returned verifier continuation on original Request cancellation" {
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(environment)
  funded_policy_subjects_prepare(parent, input, environment).unwrap() |> ignore
  let child = parent.program_check.unwrap()
  let subjects = child.policy_subjects.unwrap()
  let work = child.policy_subject_work.unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(
    child.phase == Retired &&
    child.policy_subject_work is None &&
    child.policy_subjects is None,
  )
  assert_true(
    @resources.resume_preparation_phase_work_continuation64(work) is Err(Closed),
  )
  try @checked.request_policy_subject_wire(subjects, 0) catch {
    @checked.ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("retired verifier subject remained readable")
  }
  assert_true(
    bind_request_computation_policy_subject(parent, input, environment, 0, None)
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "funded policy subjects one-byte-short prelude preserves the same original cleanup" {
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(environment)
  let child = parent.program_check.unwrap()
  let bytes = request_policy_subject_prelude_bytes(
      parent,
      child,
      request_policy_checked_program(parent),
      funded_policy_subjects_test_limits(),
    ).unwrap().0
  let before = @resources.ledger_usage(parent.ledger)
  let limit = client_local_preparation_initial_limits(
      client_local_resource_policy(),
    ).unwrap().retained_bytes
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    limit - before.reserved_retention_bytes - bytes + 1L,
    0L,
  ).unwrap()
  assert_true(
    funded_policy_subjects_prepare(parent, input, environment)
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
  assert_true(
    child.policy_subjects is None && child.policy_subject_work is None,
  )
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "funded policy subjects retain measured work when output grow loses currentness" {
  let environment = request_policy_supplement_environment()
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let (parent, input) = request_policy_supplement_fixture(environment, current=() => {
    match selected.val {
      None => true
      Some(parent) => parent.program_check.unwrap().policy_subjects is None
    }
  })
  selected.val = Some(parent)
  let child = parent.program_check.unwrap()
  assert_true(
    funded_policy_subjects_prepare(parent, input, environment) is Err(_),
  )
  assert_true(
    parent.phase == ProgramCheckFailed && child.phase == Failed && !child.busy,
  )
  assert_true(child.policy_subject_work is Some(_))
  let subjects = child.policy_subjects.unwrap()
  assert_true(@checked.request_policy_subjects_spent_work(subjects) > 0)
  assert_true(
    request_computation_policy_subject(parent, input, environment, 0)
    is Err(Preparation(ForeignOriginal)),
  )
  selected.val = None
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "funded policy subjects price original supplied Unicode output before exposing verifier DATA" {
  let environment = request_policy_supplement_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let text = policy_supplement_program
    .replace(
      old="\"type\":\"number\",\"default\":1",
      new="\"type\":\"string\",\"default\":\"\"",
    )
    .replace(
      old="\"id\":{\"$param\":\"key\"},\"tenant\":null",
      new="\"id\":1,\"tenant\":{\"$param\":\"key\"}",
    )
  let mut previous = 0L
  for length in [1, 4096] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let supplied = "{\"key\":\"" + "🙂".repeat(length) + "\"}"
    // Explicit component port: conservative original native traversal envelope,
    // not a claim that an SDK snapshot or public Source operation executed.
    reserve_request_snapshot(
      parent,
      input,
      (text.length() + supplied.length() + 32).to_int64(),
      256L,
    ).unwrap()
    prepare_request_native_computation_check(
      parent,
      input,
      request_native_test_value(text),
      native_json_reader,
      environment,
      publication,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
      supplied=Some(request_native_test_value(supplied)),
    ).unwrap()
    let parameters = parent.native_parameters.unwrap()
    let before = @resources.ledger_usage(parent.ledger)
    funded_policy_subjects_prepare(parent, input, environment).unwrap()
    |> ignore
    let after = @resources.ledger_usage(parent.ledger)
    let extra = after.reserved_retention_bytes - before.reserved_retention_bytes
    assert_true(extra > previous)
    previous = extra
    let wire = request_computation_policy_subject(parent, input, environment, 0).unwrap()
    assert_true(wire.contains("🙂".repeat(length)))
    assert_true(physical_equal(parent.native_parameters.unwrap(), parameters))
    bind_request_computation_policy_subject(parent, input, environment, 0, None).unwrap()
    finish_request_computation_policy_subjects(parent, input, environment).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "funded policy subjects fence same-parent reentry around the original current boundary" {
  let environment = request_policy_supplement_environment()
  let action : Ref[(() -> Unit)?] = Ref(None)
  let entered = Ref(false)
  let refused = Ref(false)
  let (parent, input) = request_policy_supplement_fixture(environment, current=() => {
    if !entered.val && action.val is Some(run) {
      entered.val = true
      run()
    }
    true
  })
  funded_policy_subjects_prepare(parent, input, environment).unwrap() |> ignore
  action.val = Some(() => {
    refused.val = bind_request_computation_policy_subject(
        parent,
        input,
        environment,
        0,
        None,
      )
      is Err(Preparation(ForeignOriginal)) &&
      abort_request_preparation_after_cleanup(parent) is Err(WrongPhase)
  })
  bind_request_computation_policy_subject(parent, input, environment, 0, None).unwrap()
  assert_true(entered.val && refused.val)
  finish_request_computation_policy_subjects(parent, input, environment).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "funded policy subjects preserve the original Effect child and Parameters before Plan selection" {
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(
    environment,
    effect=true,
    supplied=true,
  )
  let child = parent.program_check.unwrap()
  let program = parent.held_program.unwrap()
  let parameters = parent.native_parameters.unwrap()
  assert_true(child.effect_candidate is Some(_))
  funded_policy_subjects_prepare(parent, input, environment).unwrap() |> ignore
  bind_request_computation_policy_subject(
    parent,
    input,
    environment,
    0,
    Some(
      "sha256:bc75d87043cc6314215460b4e0f2fbf5a72363edbe989ee7bb69acfc9021c808",
    ),
  ).unwrap()
  finish_request_computation_policy_subjects(parent, input, environment).unwrap()
  assert_true(physical_equal(parent.program_check.unwrap(), child))
  assert_true(physical_equal(parent.held_program.unwrap(), program))
  assert_true(physical_equal(parent.native_parameters.unwrap(), parameters))
  assert_true(
    child.effect_candidate is Some(_) && child.compiled_effect is None,
  )
  assert_true(parent.effect_capacity is None && parent.program_capacity is None)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "funded policy subject binder cannot borrow another original Request input" {
  let environment = request_policy_supplement_environment()
  let (left, left_input) = request_policy_supplement_fixture(environment)
  let (right, right_input) = request_policy_supplement_fixture(environment)
  funded_policy_subjects_prepare(left, left_input, environment).unwrap()
  |> ignore
  funded_policy_subjects_prepare(right, right_input, environment).unwrap()
  |> ignore
  let before = @resources.ledger_usage(right.ledger)
  assert_true(
    bind_request_computation_policy_subject(
      right,
      left_input,
      environment,
      0,
      None,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(right.ledger), before)
  bind_request_computation_policy_subject(
    right,
    right_input,
    environment,
    0,
    None,
  ).unwrap()
  finish_request_computation_policy_subjects(right, right_input, environment).unwrap()
  abort_request_preparation_after_cleanup(left).unwrap()
  abort_request_preparation_after_cleanup(right).unwrap()
  assert_eq(@resources.ledger_usage(left.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(right.ledger).live_reservations, 0)
}

///|
test "funded policy subject original-current throw keeps returned work and cleanup" {
  let environment = request_policy_supplement_environment()
  let armed = Ref(false)
  let (parent, input) = request_policy_supplement_fixture(environment, current=() => {
    if armed.val {
      ignore(closed_module_test_throw())
    }
    true
  })
  funded_policy_subjects_prepare(parent, input, environment).unwrap() |> ignore
  let child = parent.program_check.unwrap()
  let original_work = child.policy_subject_work.unwrap()
  armed.val = true
  assert_true(
    bind_request_computation_policy_subject(parent, input, environment, 0, None)
    is Err(Preparation(Capacity(_))),
  )
  assert_true(
    child.phase == Failed && parent.phase == ProgramCheckFailed && !child.busy,
  )
  assert_true(physical_equal(child.policy_subject_work.unwrap(), original_work))
  assert_true(child.policy_subject_evidence.unwrap().is_empty())
  assert_true(parent.compiled_program is None && parent.compiled_effect is None)
  armed.val = false
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "funded policy subjects preserve zero static fields on the same checked Request" {
  let environment = request_policy_supplement_environment()
  let document =
    #|{"version":"actql/0.1","id":"no-static-request-fields","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
  let (parent, input) = request_policy_supplement_fixture(
    environment,
    document=Some(document),
  )
  let program = parent.held_program.unwrap()
  let child = parent.program_check.unwrap()
  let checked = request_policy_checked_program(parent)
  assert_eq(@checked.source_execution_count(checked), 0)
  assert_eq(
    funded_policy_subjects_prepare(parent, input, environment).unwrap(),
    0,
  )
  assert_true(physical_equal(parent.held_program.unwrap(), program))
  assert_true(physical_equal(parent.program_check.unwrap(), child))
  finish_request_computation_policy_subjects(parent, input, environment).unwrap()
  finish_request_computation_preparation(parent, input).unwrap()
  assert_true(parent.compiled_program is Some(_))
  assert_true(parent.program_capacity is Some(_))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "funded policy subjects admit original scan Sources with zero static request fields" {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let (parent, input) = request_policy_supplement_fixture(
    environment,
    document=Some(source_query_original_document),
  )
  let child = parent.program_check.unwrap()
  let program = parent.held_program.unwrap()
  let checked = request_policy_checked_program(parent)
  let mut requests = 0
  for index in 0..<@checked.source_execution_count(checked) {
    let source = @checked.source_execution_at(checked, index).unwrap()
    if @checked.source_execution_kind(source) is @checked.RequestEgress {
      requests += 1
      assert_eq(@checked.source_egress_field_count(source), 0)
    }
  }
  assert_true(requests > 0)
  assert_eq(
    funded_policy_subjects_prepare(parent, input, environment).unwrap(),
    0,
  )
  assert_true(physical_equal(parent.held_program.unwrap(), program))
  assert_true(physical_equal(parent.program_check.unwrap(), child))
  finish_request_computation_policy_subjects(parent, input, environment).unwrap()
  finish_request_computation_preparation(parent, input).unwrap()
  assert_true(parent.compiled_program is Some(_))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
