///|
test "reservation capacity amounts observe only the same owner's exact live token" {
  let ledger = read_capacity_fixture(10L, 7L)
  let first = reserve_attempt(ledger, 0L, 3L, 2L).unwrap()
  let second = reserve_attempt(ledger, 0L, 4L, 3L).unwrap()
  let before = ledger_usage(ledger)
  assert_eq(reservation_capacity_amounts(ledger, first).unwrap(), (3L, 2L))
  assert_eq(reservation_capacity_amounts(ledger, second).unwrap(), (4L, 3L))
  assert_eq(ledger_usage(ledger), before)
  let foreign = read_capacity_fixture(10L, 7L)
  assert_true(reservation_capacity_amounts(foreign, first) is Err(ForeignOwner))
  settle_reservation(ledger, second).unwrap()
  assert_eq(reservation_capacity_amounts(ledger, first).unwrap(), (3L, 2L))
  assert_eq(reservation_capacity_amounts(ledger, second).unwrap(), (0L, 0L))
  assert_true(
    reservation_capacity_amounts(foreign, second) is Err(ForeignOwner),
  )
  settle_reservation(ledger, first).unwrap()
}

///|
test "closed reservation capacity amounts never acknowledge a separately retained holding" {
  let ledger = read_capacity_fixture(10L, 7L)
  let reservation = reserve_attempt(ledger, 0L, 5L, 2L).unwrap()
  let holding = retain_allocation(ledger, reservation, 2L).unwrap()
  assert_eq(
    reservation_capacity_amounts(ledger, reservation).unwrap(),
    (3L, 2L),
  )
  settle_reservation(ledger, reservation).unwrap()
  let before = ledger_usage(ledger)
  assert_eq(
    reservation_capacity_amounts(ledger, reservation).unwrap(),
    (0L, 0L),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(before.held_bytes, 2L)
  assert_true(holding.live)
  release_allocation(ledger, holding).unwrap()
}
