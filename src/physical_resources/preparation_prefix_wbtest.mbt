///|
test "first Model prefix retains original preparation input IO and planning history" {
  let ledger = read_capacity_fixture(1000L, 1000L)
  let input = [1]
  let parent : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    20L,
    max_borrowers=2,
  ).unwrap()
  let identity = preparation_capacity_inventory_original(parent, input).unwrap()
  let operation = begin_preparation_io(parent, input, 3L).unwrap()
  charge_preparation_io(operation, 2L).unwrap()
  finish_preparation_io_after_cleanup(operation).unwrap()
  charge_planning(ledger, 2).unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_attempt_serial
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  assert_true(original_ledger_prefix_available(identity))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_attempt_serial, serial)
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger_usage(ledger).transferred_bytes, 2L)
  assert_eq(ledger_usage(ledger).planning_work, 2)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(abort_preparation_capacity_after_cleanup(parent, input).unwrap())
}

///|
test "preparation prefix never revives a raw zero-byte token before or after Run binding" {
  for before_binding in [false, true] {
    for capacity_only in [false, true] {
      let ledger = read_capacity_fixture(1000L, 1000L)
      let input = [1]
      let parent : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity_inventory(
        ledger,
        input,
        800L,
        20L,
        max_borrowers=2,
      ).unwrap()
      let identity = preparation_capacity_inventory_original(parent, input).unwrap()
      if !before_binding {
        claim_original_ledger_run_binding(identity, ledger).unwrap()
        assert_true(original_ledger_prefix_available(identity))
      }
      if capacity_only {
        let token = reserve_capacity(ledger, 0L, 0L).unwrap()
        settle_capacity(ledger, token).unwrap()
      } else {
        let token = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
        settle_reservation(ledger, token).unwrap()
      }
      if before_binding {
        claim_original_ledger_run_binding(identity, ledger).unwrap()
      }
      let before = ledger_usage(ledger)
      assert_false(original_ledger_prefix_available(identity))
      assert_eq(ledger_usage(ledger), before)
      assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
      assert_true(
        abort_preparation_capacity_after_cleanup(parent, input).unwrap(),
      )
    }
  }
}

///|
test "preparation input exemption ends at original Run binding and never hides Unknown transfer" {
  for unknown in [false, true] {
    let ledger = read_capacity_fixture(1000L, 1000L)
    let input = [1]
    let parent : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity_inventory(
      ledger,
      input,
      800L,
      20L,
      max_borrowers=2,
    ).unwrap()
    let identity = preparation_capacity_inventory_original(parent, input).unwrap()
    if !unknown {
      claim_original_ledger_run_binding(identity, ledger).unwrap()
    }
    let operation = begin_preparation_io(parent, input, 3L).unwrap()
    if unknown {
      mark_preparation_io_transfer_uncertain(operation).unwrap()
    }
    finish_preparation_io_after_cleanup(operation).unwrap()
    if unknown {
      claim_original_ledger_run_binding(identity, ledger).unwrap()
      assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 3L)
    }
    assert_false(original_ledger_prefix_available(identity))
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
    assert_true(
      abort_preparation_capacity_after_cleanup(parent, input).unwrap(),
    )
  }
}

///|
test "input current reentry cannot classify a foreign business token as preparation" {
  let ledger = read_capacity_fixture(1000L, 1000L)
  let input = [1]
  let parent : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    20L,
    max_borrowers=2,
  ).unwrap()
  let identity = preparation_capacity_inventory_original(parent, input).unwrap()
  let calls = Ref(0)
  let action = Ref(
    Some(() => {
      let token = reserve_capacity(ledger, 0L, 0L).unwrap()
      settle_capacity(ledger, token).unwrap()
    }),
  )
  preparation_inventory_observe_current(ledger, action, calls)
  let operation = begin_preparation_io(parent, input, 0L).unwrap()
  // Input entry, explicit reentrant reserve and its settlement, exactly once
  // each. No duplicate input current callback is hidden by the classification.
  assert_eq(calls.val, 3)
  finish_preparation_io_after_cleanup(operation).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  assert_false(original_ledger_prefix_available(identity))
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(abort_preparation_capacity_after_cleanup(parent, input).unwrap())
}

///|
test "captured keyed prefix and suffix keep absolute serials after preparation input IO" {
  // Independent logical lifetime amounts, not a physical Model/Source recipe.
  let ledger = create_ledger({
    planning_work: 3,
    attempts: 8,
    holdings: 3,
    transfer_bytes: 10L,
    retained_bytes: 1000L,
    execution_bytes: 1000L,
  }).unwrap()
  let input = [1]
  let parent : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    20L,
    max_borrowers=2,
  ).unwrap()
  let identity = preparation_capacity_inventory_original(parent, input).unwrap()
  let operation = begin_preparation_io(parent, input, 3L).unwrap()
  charge_preparation_io(operation, 2L).unwrap()
  finish_preparation_io_after_cleanup(operation).unwrap()
  grow_preparation_capacity_inventory(parent, input, 800L, 30L, 5, 3, 0).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  assert_true(original_ledger_prefix_available(identity))
  let source = reserve_attempt(ledger, 0L, 1L, 1L).unwrap()
  let source_holding = retain_allocation(ledger, source, 1L).unwrap()
  settle_reservation(ledger, source).unwrap()
  assert_eq(source.serial, 1)
  assert_true(
    original_captured_prefix_available(ledger, source, source_holding),
  )
  let prefix = reserve_attempt(ledger, 0L, 5L, 5L).unwrap()
  assert_true(
    original_ledger_captured_preparation_available(
      identity,
      prefix=Some(prefix),
    ),
  )
  let assembly = reserve_attempt(ledger, 0L, 7L, 7L).unwrap()
  assert_true(
    original_keyed_child_preparation_available(
      identity,
      ledger,
      assembly,
      0,
      prefix=Some(prefix),
    ),
  )
  let child = reserve_attempt(ledger, 0L, 2L, 2L).unwrap()
  let child_holding = retain_allocation(ledger, child, 1L).unwrap()
  settle_reservation(ledger, child).unwrap()
  assert_true(
    original_keyed_child_preparation_available(
      identity,
      ledger,
      assembly,
      1,
      prefix=Some(prefix),
    ),
  )
  assert_false(
    original_keyed_child_preparation_available(
      identity,
      ledger,
      assembly,
      0,
      prefix=Some(prefix),
    ),
  )
  let assembly_holding = retain_allocation(ledger, assembly, 1L).unwrap()
  settle_reservation(ledger, assembly).unwrap()
  assert_true(
    original_keyed_serialization_preparation_available(
      identity, ledger, prefix, assembly, 1,
    ),
  )
  let suffix = reserve_attempt(ledger, 0L, 1L, 1L).unwrap()
  assert_eq(suffix.serial, 5)
  assert_false(
    original_keyed_serialization_preparation_available(
      identity, ledger, prefix, assembly, 1,
    ),
  )
  assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
  assert_false(original_keyed_lookup_dependents_retired(ledger, assembly))
  settle_reservation(ledger, suffix).unwrap()
  assert_true(original_keyed_lookup_dependents_retired(ledger, assembly))
  release_allocation(ledger, assembly_holding).unwrap()
  release_allocation(ledger, child_holding).unwrap()
  assert_true(original_keyed_prefix_dependents_retired(ledger, prefix))
  settle_reservation(ledger, prefix).unwrap()
  release_allocation(ledger, source_holding).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(abort_preparation_capacity_after_cleanup(parent, input).unwrap())
  assert_eq(ledger.next_attempt_serial, Some(6))
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger_usage(ledger).transferred_bytes, 2L)
}

///|
test "work after original Model binding consumes prefix opportunity without changing prior history" {
  let ledger = read_capacity_fixture(1000L, 1000L)
  let input = [1]
  let parent : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    20L,
    max_borrowers=2,
  ).unwrap()
  let identity = preparation_capacity_inventory_original(parent, input).unwrap()
  charge_planning(ledger, 1).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  assert_true(original_ledger_prefix_available(identity))
  charge_planning(ledger, 0).unwrap()
  assert_true(original_ledger_prefix_available(identity))
  charge_planning(ledger, 1).unwrap()
  assert_false(original_ledger_prefix_available(identity))
  assert_eq(ledger_usage(ledger).planning_work, 2)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(abort_preparation_capacity_after_cleanup(parent, input).unwrap())
  assert_eq(ledger_usage(ledger).planning_work, 2)
}
