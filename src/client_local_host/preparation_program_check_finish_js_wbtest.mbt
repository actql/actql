///|
test "same Request completes the original remaining checker once without per-operation current callbacks" {
  let calls = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let flags = Ref(0)
  let (parent, owner, _, input) = registration_parent_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    true
  })
  let original = owner.check_registry.unwrap()
  let program = parent.held_program.unwrap()
  let before = calls.val
  action.val = Some(() => {
    if finish_program_check_preparation(owner) is Err(WrongPhase) {
      flags.val += 1
    }
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      flags.val += 2
    }
    if take_program_check_registry(owner) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  let outcome = finish_program_check_preparation(owner).unwrap()
  action.val = None
  guard outcome is @checked.Checked(checked) else {
    fail("the original supported two-Stage Program must finish checking")
  }
  assert_eq(calls.val - before, 1)
  assert_eq(flags.val, 7)
  assert_true(physical_equal(@checked.checked_source_program(checked), program))
  assert_eq(@checked.unit_count(checked), 2)
  let imported = @checked.unit_result_import_at(checked, 1, 0).unwrap()
  assert_eq(imported.producer_node_id, "a")
  assert_eq(imported.result_name, "r")
  assert_true(owner.check_work_complete && owner.work is None)
  assert_true(owner.phase == SemanticCheckComplete)
  assert_true(physical_equal(owner.capacity, parent.capacity))
  assert_true(
    @checked.parsed_check_registry_remaining_work(original)
    is Err(AlreadyConsumed),
  )
  assert_true(finish_program_check_preparation(owner) is Err(WrongPhase))
  let held = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  assert_true(held.0 > owner.base_retained && held.1 > owner.base_execution)
  clear_program_check_preparation(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input),
    Ok(held),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}

///|
test "remaining checker retains one original quote across declined grows and exact one-byte-short admission" {
  for retention in [true, false] {
    let (parent, owner, _, input) = registration_parent_fixture()
    let original = owner.check_registry.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1
      },
    ).unwrap()
    assert_true(finish_program_check_preparation(owner) is Err(Capacity(_)))
    let data = owner.check_data.unwrap()
    let quote = owner.check_quote.unwrap()
    assert_true(
      owner.phase == SemanticCheckQuoted && owner.check_outcome is None,
    )
    assert_true(
      @checked.parsed_check_registry_remaining_work(original) is Ok(_),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    let short = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - quote.0 + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - quote.1 + 1L
      },
    ).unwrap()
    let result = finish_program_check_preparation(owner)
    assert_true(
      if retention {
        result is Err(Capacity(Resource(RetentionLimit)))
      } else {
        result is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(physical_equal(owner.check_data.unwrap(), data))
    assert_eq(owner.check_quote, Some(quote))
    assert_true(
      @checked.parsed_check_registry_remaining_work(original) is Ok(_),
    )
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok(before),
    )
    @resources.settle_capacity(parent.ledger, short).unwrap()
    assert_true(
      finish_program_check_preparation(owner).unwrap() is @checked.Checked(_),
    )
    assert_true(physical_equal(owner.check_data.unwrap(), data))
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok(quote),
    )
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "remaining checker preserves the typed invalid Program outcome and consumed original without a fabricated complete failure meter" {
  let text = request_check_wire.replace(old="\"take\":1", new="\"take\":-1")
  let (parent, owner, _, _) = registration_parent_fixture(text~)
  let original = owner.check_registry.unwrap()
  let outcome = finish_program_check_preparation(owner).unwrap()
  guard outcome is @checked.Rejected(diagnostic) else {
    fail("negative Take must retain the original semantic refusal")
  }
  assert_true(
    @checked.diagnostic_cause(diagnostic) is Source(_) ||
    @checked.diagnostic_cause(diagnostic) is Closure(_) ||
    @checked.diagnostic_cause(diagnostic) is Units(_),
  )
  assert_false(owner.check_work_complete)
  assert_true(owner.phase == SemanticCheckRejected && owner.work is None)
  assert_true(
    @checked.parsed_check_registry_remaining_work(original)
    is Err(AlreadyConsumed),
  )
  assert_true(finish_program_check_preparation(owner) is Err(WrongPhase))
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "completed check handoff retains original Program and backing while the parent cannot retire its successor" {
  let (parent, owner, _, input) = registration_parent_fixture()
  let outcome = finish_program_check_preparation(owner).unwrap()
  let held = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  let (taken, complete) = take_program_check_preparation_outcome(owner).unwrap()
  assert_true(physical_equal(outcome, taken) && complete)
  assert_true(
    owner.check_outcome is None &&
    owner.input is None &&
    owner.phase == Transferred,
  )
  assert_true(take_program_check_preparation_outcome(owner) is Err(WrongPhase))
  clear_program_check_preparation(owner).unwrap()
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input),
    Ok(held),
  )
  // This fixture's successor has now dropped its returned DATA. Only the same
  // original capacity retirement can release its reservation; no replacement.
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(parent.capacity, input).unwrap(),
  )
  preparation_initial_cleanup(parent.initial).unwrap()
}

///|
test "remaining check handles one thousand Values rows and a long ordered Pipe under the unchanged ordinary policy" {
  let rows : Array[String] = []
  for i in 0..<1000 {
    rows.push("{\"id\":" + i.to_string() + "}")
  }
  let steps : Array[String] = []
  for i in 0..<40 {
    steps.push("{\"select\":[\"id\"],\"as\":\"p" + i.to_string() + "\"}")
  }
  let text = request_check_wire
    .replace(old="\"rows\":[]", new="\"rows\":[" + rows.join(",") + "]")
    .replace(old="{\"take\":1,\"as\":\"t\"}", new=steps.join(","))
    .replace(old="\"from\":\"t\"", new="\"from\":\"p39\"")
  let (parent, owner, _, input) = registration_parent_fixture(text~)
  let policy = @resources.ledger_limits(parent.ledger)
  let outcome = finish_program_check_preparation(owner).unwrap()
  guard outcome is @checked.Checked(checked) else {
    fail("large Values plus ordered Pipe must keep its original supported path")
  }
  assert_eq(@checked.unit_count(checked), 2)
  let held = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  assert_true(
    held.0 <= policy.retained_bytes && held.1 <= policy.execution_bytes,
  )
  assert_true(owner.check_work_complete)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "remaining check refuses an original registry consumed inside its single current callback" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, owner, _, _) = registration_parent_fixture(current=() => {
    if action.val is Some(run) {
      run()
    }
    true
  })
  let original = owner.check_registry.unwrap()
  action.val = Some(() => {
    @checked.finish_parsed_check_registry(original) |> ignore
  })
  assert_true(finish_program_check_preparation(owner) is Err(ChangedInputs))
  action.val = None
  assert_true(
    owner.phase == Failed && owner.check_outcome is None && owner.work is None,
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
