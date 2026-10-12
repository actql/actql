///|
test "original invalidation intent is exact one outstanding and retains unresolved custody" {
  let (ledger, origin, claim, consumer) = current_state_test_consumer(17)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  let request = begin_original_resource_invalidation(park, origin).unwrap()
  for _ in 0..<3 {
    assert_true(
      original_resource_invalidation_current(request, park, origin)
      is Some(same) &&
      physical_equal(same, request),
    )
    assert_true(
      begin_original_resource_invalidation(park, origin) is Err(SpentClaim),
    )
    assert_eq(charge_planning(ledger, 1), Err(ResourceParked))
    assert_eq(
      stop_funded_read_consumer(consumer),
      Err(Resource(ResourceParked)),
    )
    assert_eq(
      settle_funded_read_consumer(consumer, false),
      Err(Resource(ResourceParked)),
    )
    assert_eq(retire_original_resource_park(park), Err(CleanupPending))
    assert_eq(ledger_usage(ledger), before)
    assert_eq(ledger.next_capacity_serial, serial)
    assert_true(claim.phase is ConsumerParked(_, _) && request.park is Some(_))
  }
  // No receipt is supplied here. Pending/Unknown responsibility remains live.
}

///|
test "original invalidation intent rejects foreign copied and stale handles without mutation" {
  let (ledger, origin, _, consumer) = current_state_test_consumer(17)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let request = begin_original_resource_invalidation(park, origin).unwrap()
  let copy : OriginalResourceInvalidationRequest[OriginalReadTestOrigin] = {
    park: request.park,
  }
  let (other_ledger, other_origin, _, other_consumer) = current_state_test_consumer(
    17,
  )
  let other_park = park_original_resource_consumer(other_consumer, other_origin).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    original_resource_invalidation_current(copy, park, origin) is None,
  )
  assert_eq(
    consume_original_resource_invalidation(copy, park, origin),
    Err(ChangedOriginalState),
  )
  assert_eq(
    consume_original_resource_invalidation(request, other_park, origin),
    Err(ChangedOriginalState),
  )
  assert_eq(
    consume_original_resource_invalidation(request, park, other_origin),
    Err(ChangedOriginalState),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(
    original_resource_invalidation_current(request, park, origin) is Some(_),
  )
  // Private fixture simulates loss of currentness, not a real journal COMMIT.
  resource_park_test_invalidate(park)
  assert_true(
    original_resource_invalidation_current(request, park, origin) is None,
  )
  assert_eq(
    consume_original_resource_invalidation(request, park, origin),
    Err(ChangedOriginalState),
  )
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  assert_true(request.park is None && park.invalidation is None)
  // A forged local test copy is not owned by the park; explicitly drop it.
  copy.park = None
  resource_park_test_invalidate(other_park)
  settle_funded_read_consumer(other_consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(other_ledger, true).unwrap())
  retire_original_resource_park(other_park).unwrap()
}

///|
// This exercises the INTERNAL Resource transition only, assuming its trusted
// caller has already authenticated the original COMMIT. It is NOT actual
// journal authentication, restart, permission to send, or public acceptance.
test "original invalidation inner consume is once with unknown quantity and serial unchanged" {
  let ledger = resource_park_test_ledger()
  let origin = original_read_test_origin()
  let amounts : QuantityAmounts = {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }
  configure_quantities(ledger, amounts).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 16, 0, 0).unwrap()
  let send = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  mark_quantities_uncertain(ledger, send).unwrap()
  let spent = reserve_capacity(ledger, 0L, 0L).unwrap()
  settle_capacity(ledger, spent).unwrap()
  let (_, consumer) = resource_park_test_consumer(identity, origin)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let request = begin_original_resource_invalidation(park, origin).unwrap()
  let usage = ledger_usage(ledger)
  let quantities = quantity_usage(ledger)
  let serial = ledger.next_capacity_serial
  consume_original_resource_invalidation(request, park, origin).unwrap()
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(quantity_usage(ledger), quantities)
  assert_eq(quantity_usage(ledger).uncertain, amounts)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_true(
    request.park is None &&
    park.invalidation is None &&
    park.consumer is None &&
    park.origin is None &&
    park.fence is None &&
    park.previous is None,
  )
  assert_true(original_resource_park_current(park, origin) is None)
  assert_true(
    original_resource_invalidation_current(request, park, origin) is None,
  )
  assert_eq(
    consume_original_resource_invalidation(request, park, origin),
    Err(SpentClaim),
  )
  assert_eq(ledger_usage(ledger), usage)
  assert_true(consumer.claim is Some(_))
  assert_eq(settle_funded_read_consumer(consumer, false), Err(CleanupPending))
  settle_reservation(ledger, send).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original invalidation inner consume restores stopping not a fresh execution" {
  let (ledger, origin, claim, consumer) = current_state_test_consumer(17)
  stop_funded_read_consumer(consumer).unwrap()
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let request = begin_original_resource_invalidation(park, origin).unwrap()
  let before = ledger_usage(ledger)
  consume_original_resource_invalidation(request, park, origin).unwrap()
  assert_true(claim.phase is ConsumerStopping(_))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(settle_funded_read_consumer(consumer, false), Err(CleanupPending))
  assert_true(consumer.claim is Some(_))
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(request.park is None)
}
