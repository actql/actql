///|
fn original_inventory_live_fixture() -> (
  Ledger,
  CapacityReservation,
  OriginalLedgerIdentity,
) {
  let ledger = resource_park_test_ledger()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  (ledger, bootstrap, identity)
}

///|
test "original inventory live keeps issued original custody without mutation" {
  let (ledger, _, identity) = original_inventory_live_fixture()
  assert_true(original_ledger_inventory_live(identity))
  let origin = original_read_test_origin()
  issue_recorded_original_ledger_descriptor(identity, origin).unwrap() |> ignore
  let usage = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  let inventory = ledger.original_inventory.unwrap()
  assert_true(inventory.descriptor_issued)
  assert_false(inventory.read_claimed)
  assert_true(original_ledger_inventory_live(identity))
  assert_true(original_ledger_inventory_available(identity))
  assert_false(original_ledger_prefix_available(identity))
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_true(physical_equal(ledger.original_inventory.unwrap(), inventory))
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_false(original_ledger_inventory_live(identity))
}

///|
test "original inventory live allows parked borrow but cannot allocate or unpark" {
  let (ledger, _, identity) = original_inventory_live_fixture()
  let origin = original_read_test_origin()
  let (_, consumer) = resource_park_test_consumer(identity, origin)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let usage = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  let fence = ledger.original_inventory.unwrap().park.unwrap()
  assert_true(original_ledger_inventory_live(identity))
  assert_false(original_ledger_inventory_available(identity))
  assert_false(original_ledger_prefix_available(identity))
  assert_true(reserve_capacity(ledger, 0L, 0L) is Err(ResourceParked))
  assert_true(
    issue_recorded_original_ledger_descriptor(identity, origin)
    is Err(Resource(ResourceParked)),
  )
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_true(physical_equal(ledger.original_inventory.unwrap().park.unwrap(), fence))
  assert_true(original_resource_park_current(park, origin) is Some(_))
  // Existing WB-only invalidation is not a journal COMMIT/admission receipt.
  resource_park_test_invalidate(park)
  assert_true(original_ledger_inventory_live(identity))
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  assert_false(original_ledger_inventory_live(identity))
}

///|
test "original inventory live rejects copied foreign and swapped bootstrap identities" {
  let (ledger, bootstrap, identity) = original_inventory_live_fixture()
  let copied : OriginalLedgerIdentity = { ledger, bootstrap, }
  assert_false(original_ledger_inventory_live(copied))
  let (foreign_ledger, foreign_bootstrap, foreign_identity) = original_inventory_live_fixture()
  let swapped : OriginalLedgerIdentity = {
    ledger,
    bootstrap: foreign_bootstrap,
  }
  assert_false(original_ledger_inventory_live(swapped))
  assert_true(original_ledger_inventory_live(identity))
  assert_true(original_ledger_inventory_live(foreign_identity))
  let inventory = ledger.original_inventory.unwrap()
  // A bad backend record cannot replace the actual bootstrap by matching data.
  ledger.original_inventory = Some({ ..inventory, bootstrap: foreign_bootstrap, })
  assert_false(original_ledger_inventory_live(identity))
  ledger.original_inventory = Some(inventory)
  assert_true(original_ledger_inventory_live(identity))
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(finish_original_ledger_inventory(foreign_ledger, true).unwrap())
}

///|
test "original inventory live rejects pending final close and reclaimed bootstrap" {
  let (ledger, bootstrap, identity) = original_inventory_live_fixture()
  assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
  let usage = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  assert_true(capacity_reservation_open(bootstrap))
  assert_false(original_ledger_inventory_live(identity))
  assert_false(original_ledger_inventory_available(identity))
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_false(capacity_reservation_open(bootstrap))
  assert_false(original_ledger_inventory_live(identity))
}

///|
test "original inventory live never resets spent serial or unknown quantities" {
  let ledger = resource_park_test_ledger()
  let amounts : QuantityAmounts = {
    tokens: 3L,
    cost_units: 2L,
    duration_ms: 7L,
  }
  configure_quantities(ledger, amounts).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let dispatched = reserve_attempt(
    ledger, 0L, 0L, 0L, quantities=Some(amounts),
  ).unwrap()
  mark_quantities_uncertain(ledger, dispatched).unwrap()
  let spent = reserve_capacity(ledger, 0L, 0L).unwrap()
  settle_capacity(ledger, spent).unwrap()
  let usage = ledger_usage(ledger)
  let quantities = quantity_usage(ledger)
  let serial = ledger.next_capacity_serial
  assert_eq(quantities.uncertain, amounts)
  assert_true(original_ledger_inventory_live(identity))
  assert_true(original_ledger_inventory_live(identity))
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(quantity_usage(ledger), quantities)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_false(original_ledger_prefix_available(identity))
  // Preserve entered uncertainty and its same original cleanup responsibility.
  assert_false(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_false(original_ledger_inventory_live(identity))
  assert_eq(quantity_usage(ledger), quantities)
}
