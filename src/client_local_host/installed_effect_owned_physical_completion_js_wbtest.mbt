///|
// These tests use the existing real Plan, preparation, Resource and operation
// fixture. Its explicit no-I/O cleanup observation is not Native/FS evidence.
#cfg(target="js")
test "owned physical completion returns only workspace and keeps the spent original until cleanup" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
    physical_initial=Some(@execution.execution_capacity(9L, 48L).unwrap()),
    current=() => calls.val += 1,
  )
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  guard child.backing
    is Some(@resources.NodeManagedRunOperationBacking::Physical(original)) else {
    fail("original physical token missing")
  }
  assert_false(child.started)
  assert_false(child.input_selected)
  start_installed_effect_operation(child).unwrap()
  charge_installed_effect_operation(child, 2L).unwrap()
  @resources.mark_transfer_uncertain(ledger, original, 1L).unwrap()
  @resources.mark_cleanup_pending(ledger, original).unwrap()
  let before = @resources.ledger_usage(ledger)
  let current = calls.val
  assert_eq(
    @resources.reservation_capacity_amounts(ledger, original).unwrap(),
    (9L, 48L),
  )
  complete_installed_effect_owned_physical_operation(child).unwrap()
  assert_eq(calls.val, current + 1)
  let after = @resources.ledger_usage(ledger)
  assert_eq(after, {
    ..before,
    reserved_execution_bytes: before.reserved_execution_bytes - (48L - 9L),
  })
  assert_eq(
    @resources.reservation_capacity_amounts(ledger, original).unwrap(),
    (9L, 9L),
  )
  guard child.backing
    is Some(@resources.NodeManagedRunOperationBacking::Physical(same)) else {
    fail("completed physical token missing")
  }
  assert_true(physical_equal(same, original))
  assert_true(child.started && !child.input_selected && !child.retired)
  assert_true(@resources.reservation_open(original))
  assert_true(@resources.reservation_pending(original))
  // The staged response entrance does not gain a new unstaged admission.
  assert_true(
    complete_installed_effect_operation_response_projection(child)
    is Err(Unsupported),
  )
  assert_true(
    complete_installed_effect_operation_construction(child) is Err(Unsupported),
  )
  complete_installed_effect_owned_physical_operation(child).unwrap()
  assert_eq(@resources.ledger_usage(ledger), after)
  assert_true(start_installed_effect_operation(child) is Err(AlreadyBound))
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 0, 0, "send",
    )
    is Err(AlreadyBound),
  )
  assert_eq(@resources.ledger_usage(ledger), after)
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_eq(@resources.ledger_usage(ledger), after)
  // Only the fixture's existing explicit original-cleanup gate settles the
  // reservation. Completion above supplied no close or physical ACK itself.
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.live_reservations, 0)
  assert_eq(retired.attempts, before.attempts)
  assert_eq(retired.transferred_bytes, before.transferred_bytes)
  assert_eq(retired.uncertain_transfer_bytes, before.uncertain_transfer_bytes)
}

///|
#cfg(target="js")
test "owned physical completion refuses copied unstarted construction and retired originals" {
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
    physical_initial=Some(@execution.execution_capacity(9L, 48L).unwrap()),
  )
  let construction = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, false, 0, 0, "capture",
  ).unwrap()
  let construction_usage = @resources.ledger_usage(ledger)
  assert_true(
    complete_installed_effect_owned_physical_operation(construction)
    is Err(Unsupported),
  )
  assert_eq(@resources.ledger_usage(ledger), construction_usage)
  assert_true(retire_installed_effect_operation(construction, true).unwrap())
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    complete_installed_effect_owned_physical_operation(child)
    is Err(Unsupported),
  )
  assert_true(
    complete_installed_effect_owned_physical_operation({ ..child, })
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  start_installed_effect_operation(child).unwrap()
  let started = @resources.ledger_usage(ledger)
  assert_true(
    complete_installed_effect_owned_physical_operation({ ..child, })
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), started)
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  let retired = @resources.ledger_usage(ledger)
  assert_true(
    complete_installed_effect_owned_physical_operation(child) is Err(Retired),
  )
  assert_eq(@resources.ledger_usage(ledger), retired)
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
#cfg(target="js")
test "owned physical completion keeps its full prefix through closing and current retirement refusal" {
  let selected : Ref[ClientInstalledEffectOperationBorrow?] = Ref(None)
  let retire_during_current = Ref(false)
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
    physical_initial=Some(@execution.execution_capacity(9L, 48L).unwrap()),
    current=() => {
      calls.val += 1
      if retire_during_current.val {
        selected.val.unwrap().retired = true
      }
    },
  )
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  selected.val = Some(child)
  start_installed_effect_operation(child).unwrap()
  charge_installed_effect_operation(child, 2L).unwrap()
  let before = @resources.ledger_usage(ledger)
  owner.effect_operation_opening = true
  assert_true(
    complete_installed_effect_owned_physical_operation(child)
    is Err(AlreadyBound),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  owner.effect_operation_opening = false
  owner.effect_operation_closing = true
  assert_true(
    complete_installed_effect_owned_physical_operation(child)
    is Err(AlreadyBound),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  owner.effect_operation_closing = false
  let current = calls.val
  retire_during_current.val = true
  assert_true(
    complete_installed_effect_owned_physical_operation(child) is Err(Retired),
  )
  assert_eq(calls.val, current + 1)
  assert_eq(@resources.ledger_usage(ledger), before)
  // Restore only this white-box current fault for the existing cleanup path.
  // No replacement operation, reservation or cleanup observation is created.
  retire_during_current.val = false
  child.retired = false
  complete_installed_effect_owned_physical_operation(child).unwrap()
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
