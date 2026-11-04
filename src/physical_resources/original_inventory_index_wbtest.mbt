///|
fn indexed_original_test_ledger() -> Ledger {
  let ledger = create_ledger({
    planning_work: 1000,
    attempts: 100,
    holdings: 100,
    transfer_bytes: 1000L,
    retained_bytes: 1000000L,
    execution_bytes: 1000000L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 10000L, 10000L).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, 8, 2, 2).unwrap() |> ignore
  ledger
}

///|
test "indexed originals retain live issuance order across an observed cut and subsequent retirement" {
  let ledger = indexed_original_test_ledger()
  let inventory = ledger.original_inventory.unwrap()
  let originals = Array::makei(4, _ => reserve_capacity(ledger, 0L, 0L).unwrap())
  // Force an actual ordinal read before the mutation, then read the new cut.
  assert_true(
    physical_equal(inventory.reservations[1], originals[1].reservation),
  )
  settle_capacity(ledger, originals[1]).unwrap()
  let last = reserve_capacity(ledger, 0L, 0L).unwrap()
  let expected = [
    originals[0].reservation,
    originals[2].reservation,
    originals[3].reservation,
    last.reservation,
  ]
  assert_eq(inventory.reservations.length(), expected.length())
  for index, original in expected {
    assert_true(physical_equal(inventory.reservations[index], original))
  }
  // Matching owner/serial DATA in a copied record does not remove an original.
  let copied : Reservation = { ..last.reservation, }
  retire_original_reservation(ledger, copied)
  assert_true(
    physical_equal(
      inventory.reservations.by_serial(last.reservation.serial).unwrap(),
      last.reservation,
    ),
  )
  let foreign = indexed_original_test_ledger()
  let foreign_reservation = reserve_capacity(foreign, 0L, 0L).unwrap()
  retire_original_reservation(ledger, foreign_reservation.reservation)
  assert_eq(inventory.reservations.length(), expected.length())
  for original in expected {
    settle_reservation(ledger, original).unwrap()
  }
  assert_true(inventory.reservations.is_empty())
  assert_eq(ledger_usage(ledger).live_reservations, 1)
}

///|
test "indexed originals retain a closed reservation until its last actual zero-byte holding retires" {
  let ledger = indexed_original_test_ledger()
  let inventory = ledger.original_inventory.unwrap()
  let original = reserve_attempt(ledger, 5L, 3L, 0L).unwrap()
  charge_planning(ledger, 7).unwrap()
  charge_transfer(ledger, original, 2L).unwrap()
  let first = retain_allocation(ledger, original, 0L).unwrap()
  let last = retain_allocation(ledger, original, 3L).unwrap()
  let full = ledger_usage(ledger)
  assert_true(retain_allocation(ledger, original, 0L) is Err(RetentionLimit))
  assert_eq(ledger_usage(ledger), full)
  settle_reservation(ledger, original).unwrap()
  assert_true(
    physical_equal(
      inventory.reservations.by_serial(original.serial).unwrap(),
      original,
    ),
  )
  assert_eq(
    inventory.holding_counts.get(OriginalTokenSerial(original.serial)),
    Some(2),
  )
  let copied : Holding = { ..first, }
  retire_original_holding(ledger, copied)
  assert_eq(
    inventory.holding_counts.get(OriginalTokenSerial(original.serial)),
    Some(2),
  )
  release_allocation(ledger, first).unwrap()
  assert_eq(
    inventory.holding_counts.get(OriginalTokenSerial(original.serial)),
    Some(1),
  )
  assert_true(inventory.reservations.by_serial(original.serial) is Some(_))
  release_allocation(ledger, last).unwrap()
  assert_true(inventory.reservations.is_empty())
  assert_true(inventory.holdings.is_empty())
  assert_true(inventory.holding_counts.is_empty())
  let usage = ledger_usage(ledger)
  assert_eq(usage.attempts, 1)
  assert_eq(usage.transferred_bytes, 2L)
  assert_eq(usage.planning_work, 7)
  assert_eq(ledger.next_attempt_serial, Some(1))
  assert_eq(ledger.next_holding_serial, Some(2))
  let replacement = reserve_capacity(ledger, 0L, 0L).unwrap()
  assert_true(replacement.reservation.serial != original.serial)
  assert_true(
    physical_equal(inventory.reservations[0], replacement.reservation),
  )
}

///|
test "indexed originals unlink only their original delegation and preserve consumed provisioning history" {
  let ledger = indexed_original_test_ledger()
  let inventory = ledger.original_inventory.unwrap()
  let limits : LedgerLimits = {
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }
  let final_usage = ledger_usage(create_ledger(limits).unwrap())
  let first = reserve_execution_delegation(ledger, limits, 0L, 0L).unwrap()
  let second = reserve_execution_delegation(ledger, limits, 0L, 0L).unwrap()
  let copied : ExecutionDelegation = { ..first, }
  retire_original_delegation(ledger, copied)
  assert_eq(inventory.delegations.length(), 2)
  consume_execution_delegation_attempt(ledger, first).unwrap()
  settle_execution_delegation(ledger, first, Some(final_usage)).unwrap()
  assert_true(physical_equal(inventory.delegations[0], second))
  settle_execution_delegation(ledger, second, Some(final_usage)).unwrap()
  assert_true(inventory.delegations.is_empty())
  assert_true(inventory.reservations.is_empty())
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger.next_attempt_serial, Some(2))
}

///|
test "original serial keys have fixed full-range hashes and preserve distinct signed keys" {
  let serials = [-2147483648, -2, -1, 0, 1, 2147483647]
  let values : Map[OriginalTokenSerial, Int] = Map([])
  for index, serial in serials {
    let key = OriginalTokenSerial(serial)
    // Independent fixed vectors: the inventory hash is this exact scalar,
    // without consulting the process/module's builtin Int hashing seed.
    assert_eq(Hash::hash(key), serial)
    values[key] = index
  }
  for index, serial in serials {
    assert_eq(values.get(OriginalTokenSerial(serial)), Some(index))
  }
  assert_eq(values.length(), serials.length())
}
