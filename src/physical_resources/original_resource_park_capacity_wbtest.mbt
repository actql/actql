///|
test "parked original read capacity checks the exact token not aggregate free space" {
  let ledger = resource_park_test_ledger()
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let (claim, consumer) = resource_park_test_consumer(identity, origin)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let before = original_ledger_snapshot(ledger)
  let read_before = original_reservation_snapshot(claim.read.reservation)
  for _ in 0..<3 {
    assert_true(
      original_resource_park_read_capacity_covers(park, origin, 7L, 5L),
    )
    assert_false(
      original_resource_park_read_capacity_covers(park, origin, 8L, 5L),
    )
    assert_false(
      original_resource_park_read_capacity_covers(park, origin, 7L, 6L),
    )
    assert_false(
      original_resource_park_read_capacity_covers(park, origin, -1L, 5L),
    )
    assert_false(
      original_resource_park_read_capacity_covers(park, origin, 7L, -1L),
    )
    assert_false(
      funded_read_preparation_available(claim, origin, 5L, retained_bytes=7L),
    )
  }
  assert_true(original_ledger_snapshot(ledger) == before)
  assert_true(
    original_reservation_snapshot(claim.read.reservation) == read_before,
  )
  assert_true(
    claim.phase is ConsumerParked(_, same) && physical_equal(same, park),
  )
  resource_park_test_invalidate(park)
  assert_false(
    original_resource_park_read_capacity_covers(park, origin, 7L, 5L),
  )
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  assert_false(
    original_resource_park_read_capacity_covers(park, origin, 0L, 0L),
  )
}

///|
test "parked original read capacity rejects copied foreign and changed original handles" {
  let ledger = resource_park_test_ledger()
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let (claim, consumer) = resource_park_test_consumer(identity, origin)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let copy : OriginalResourcePark[OriginalReadTestOrigin] = {
    consumer: park.consumer,
    origin: park.origin,
    fence: park.fence,
    previous: park.previous,
    state_write_work: park.state_write_work,
    invalidation: park.invalidation,
  }
  assert_false(
    original_resource_park_read_capacity_covers(copy, origin, 7L, 5L),
  )
  assert_false(
    original_resource_park_read_capacity_covers(
      park,
      original_read_test_origin(),
      7L,
      5L,
    ),
  )
  // Private mutation fixture: product mutators cannot change a parked read.
  claim.read.reservation.cleanup_pending = true
  assert_false(
    original_resource_park_read_capacity_covers(park, origin, 7L, 5L),
  )
  claim.read.reservation.cleanup_pending = false
  claim.read.reservation.retention = 8L
  assert_false(
    original_resource_park_read_capacity_covers(park, origin, 7L, 5L),
  )
  claim.read.reservation.retention = 7L
  assert_true(original_resource_park_read_capacity_covers(park, origin, 7L, 5L))
  resource_park_test_invalidate(park)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  retire_original_resource_park(copy).unwrap()
}

///|
test "parked original read capacity preserves stopping and cleanup pending responsibility" {
  let ledger = resource_park_test_ledger()
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let (claim, consumer) = resource_park_test_consumer(identity, origin)
  stop_funded_read_consumer(consumer).unwrap()
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let before = original_ledger_snapshot(ledger)
  assert_true(original_resource_park_read_capacity_covers(park, origin, 7L, 5L))
  assert_eq(
    settle_funded_read_consumer(consumer, false),
    Err(Resource(ResourceParked)),
  )
  assert_true(original_resource_park_read_capacity_covers(park, origin, 7L, 5L))
  assert_true(original_ledger_snapshot(ledger) == before)
  assert_true(claim.phase is ConsumerParked(_, _))
  resource_park_test_invalidate(park)
  assert_true(claim.phase is ConsumerStopping(_))
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
}
