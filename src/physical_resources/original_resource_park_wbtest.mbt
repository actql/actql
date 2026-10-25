///|
fn resource_park_test_ledger() -> Ledger {
  create_ledger({
    planning_work: 100,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 100L,
    retained_bytes: 256L,
    execution_bytes: 256L,
  }).unwrap()
}

///|
fn resource_park_test_consumer(
  identity : OriginalLedgerIdentity,
  origin : OriginalReadTestOrigin,
) -> (
  FundedReadClaim[OriginalReadTestOrigin],
  FundedReadConsumer[OriginalReadTestOrigin],
) {
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(identity.ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  (claim, consumer)
}

///|
// Private test fixture only: simulate an already authenticated invalidation.
// There is intentionally NO product unpark/admission API until A's actual
// same-journal COMMIT receipt bridge is implemented/reviewed. This helper is
// not evidence of durable COMMIT, Store ACK, restoration or send permission.
fn resource_park_test_invalidate(
  value : OriginalResourcePark[OriginalReadTestOrigin],
) -> Unit raise {
  let consumer = value.consumer.unwrap()
  let claim = consumer.claim.unwrap()
  let fence = value.fence.unwrap()
  let inventory = claim.descriptor.ledger.original_inventory.unwrap()
  assert_true(physical_equal(inventory.park.unwrap(), fence))
  claim.phase = value.previous.unwrap()
  inventory.park = None
}

///|
test "original Resource park freezes current ledger tokens shared readers and delegated facts" {
  let ledger = resource_park_test_ledger()
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 16, 4, 4).unwrap()
  let send = reserve_attempt(ledger, 11L, 7L, 5L).unwrap()
  let holding = retain_allocation(ledger, send, 3L).unwrap()
  let shared = reserve_shared_capacity(ledger, 32L).unwrap()
  let allocation = allocate_shared_capacity(shared, 4L).unwrap()
  let borrowed = borrow_shared_capacity(shared, allocation).unwrap()
  let delegation = reserve_execution_delegation(
    ledger,
    {
      planning_work: 2,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 3L,
      retained_bytes: 2L,
      execution_bytes: 2L,
    },
    2L,
    2L,
  ).unwrap()
  let (claim, consumer) = resource_park_test_consumer(identity, origin)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  assert_true(
    original_resource_park_current_for_ledger(park, ledger) is Some(same) &&
    physical_equal(same, park),
  )
  assert_true(
    original_resource_park_current_for_ledger(park, resource_park_test_ledger())
    is None,
  )
  let usage = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  let send_before = original_reservation_snapshot(send)
  let delegated = original_delegation_snapshot(delegation)
  let shared_before = shared_capacity_usage(shared)
  let allocation_before = shared_allocation_usage(allocation)
  assert_true(
    original_resource_park_current(park, origin) is Some(same) &&
    physical_equal(same, park),
  )
  assert_eq(charge_planning(ledger, 1), Err(ResourceParked))
  assert_true(reserve_attempt(ledger, 1L, 1L, 1L) is Err(ResourceParked))
  assert_true(reserve_capacity(ledger, 0L, 0L) is Err(ResourceParked))
  assert_eq(charge_transfer(ledger, send, 1L), Err(ResourceParked))
  assert_eq(mark_transfer_uncertain(ledger, send, 1L), Err(ResourceParked))
  assert_true(retain_allocation(ledger, send, 1L) is Err(ResourceParked))
  assert_eq(mark_cleanup_pending(ledger, send), Err(ResourceParked))
  assert_eq(settle_reservation(ledger, send), Err(ResourceParked))
  assert_eq(release_allocation(ledger, holding), Err(ResourceParked))
  assert_true(allocate_shared_capacity(shared, 1L) is Err(ResourceParked))
  assert_true(borrow_shared_capacity(shared, allocation) is Err(ResourceParked))
  assert_eq(retire_shared_capacity(allocation), Err(ResourceParked))
  assert_eq(return_shared_capacity(borrowed), Err(ResourceParked))
  assert_eq(release_shared_capacity(allocation), Err(ResourceParked))
  assert_eq(close_shared_capacity(shared), Err(ResourceParked))
  assert_eq(
    report_execution_delegation(ledger, delegation, {
      planning_work: 1,
      attempts: 0,
      holdings: 0,
      reserved_attempts: 0,
      live_reservations: 0,
      live_delegations: 0,
      transferred_bytes: 0L,
      uncertain_transfer_bytes: 0L,
      reserved_transfer_bytes: 3L,
      held_bytes: 0L,
      reserved_retention_bytes: 2L,
      reserved_execution_bytes: 2L,
      peak_retention_bytes: 2L,
    }),
    Err(ResourceParked),
  )
  assert_eq(
    settle_execution_delegation(ledger, delegation, None),
    Err(ResourceParked),
  )
  assert_eq(stop_funded_read_consumer(consumer), Err(Resource(ResourceParked)))
  assert_eq(settle_funded_read(claim, false), Err(Resource(ResourceParked)))
  assert_eq(settle_funded_read(claim, true), Err(Resource(ResourceParked)))
  assert_eq(
    finish_original_ledger_inventory(ledger, true),
    Err(Resource(ResourceParked)),
  )
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_true(original_reservation_snapshot(send) == send_before)
  assert_eq(original_delegation_snapshot(delegation), delegated)
  assert_eq(shared_capacity_usage(shared).allocated, shared_before.allocated)
  assert_eq(
    shared_allocation_usage(allocation).readers,
    allocation_before.readers,
  )
  assert_false(borrowed.returned)
  assert_false(allocation.retiring || allocation.released || shared.closing)
  assert_false(ledger.original_inventory.unwrap().closing)
  assert_true(holding.live && consumer.claim is Some(_))
  assert_eq(retire_original_resource_park(park), Err(CleanupPending))
  resource_park_test_invalidate(park)
  assert_true(original_resource_park_current_for_ledger(park, ledger) is None)
  assert_true(original_resource_park_current(park, origin) is None)
  assert_true(original_resource_park_origin(park) is None)
  return_shared_capacity(borrowed).unwrap()
  retire_shared_capacity(allocation).unwrap()
  release_shared_capacity(allocation).unwrap()
  close_shared_capacity(shared).unwrap()
  settle_shared_capacity(shared).unwrap()
  settle_execution_delegation(ledger, delegation, None).unwrap()
  release_allocation(ledger, holding).unwrap()
  settle_reservation(ledger, send).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  assert_true(
    park.consumer is None &&
    park.fence is None &&
    park.origin is None &&
    park.previous is None,
  )
  assert_eq(retire_original_resource_park(park), Err(SpentClaim))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "original Resource park rejects foreign copied phase and repeated handles after handoff" {
  let ledger = resource_park_test_ledger()
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let (claim, consumer) = resource_park_test_consumer(identity, origin)
  let (_, capacity) = handoff_funded_read_consumer_capacity(
    consumer, origin, 1L, 1L,
  ).unwrap()
  assert_true(funded_read_consumer_origin(consumer) is None)
  let forged : FundedReadConsumer[OriginalReadTestOrigin] = {
    claim: Some(claim),
  }
  assert_true(
    park_original_resource_consumer(forged, origin) is Err(ChangedOriginalState),
  )
  assert_true(
    park_original_resource_consumer(consumer, original_read_test_origin())
    is Err(ForeignOrigin),
  )
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  assert_true(
    original_resource_park_origin(park) is Some(same) &&
    physical_equal(same, origin),
  )
  let copy : OriginalResourcePark[OriginalReadTestOrigin] = {
    consumer: park.consumer,
    origin: park.origin,
    fence: park.fence,
    previous: park.previous,
    state_write_work: park.state_write_work,
    invalidation: park.invalidation,
  }
  assert_true(original_resource_park_current(copy, origin) is None)
  assert_true(original_resource_park_current_for_ledger(copy, ledger) is None)
  assert_true(original_resource_park_origin(copy) is None)
  assert_true(park_original_resource_consumer(consumer, origin) is Err(_))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_true(settle_capacity(ledger, capacity) is Err(ResourceParked))
  assert_eq(retire_original_resource_park(park), Err(CleanupPending))
  resource_park_test_invalidate(park)
  assert_eq(retire_original_resource_park(park), Err(CleanupPending))
  settle_capacity(ledger, capacity).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  retire_original_resource_park(copy).unwrap()
  assert_true(original_resource_park_current_for_ledger(park, ledger) is None)
  assert_true(
    park.consumer is None &&
    park.fence is None &&
    park.origin is None &&
    park.previous is None,
  )
  assert_true(
    park_original_resource_consumer(consumer, origin) is Err(SpentClaim),
  )
}

///|
test "original Resource park keeps unknown quantities spent serials and primary observation for retry" {
  let ledger = resource_park_test_ledger()
  let origin = original_read_test_origin()
  let amounts : QuantityAmounts = {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }
  configure_quantities(ledger, amounts).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let send = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  mark_quantities_uncertain(ledger, send).unwrap()
  let spent = reserve_capacity(ledger, 0L, 0L).unwrap()
  settle_capacity(ledger, spent).unwrap()
  let (claim, consumer) = resource_park_test_consumer(identity, origin)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let serial = ledger.next_capacity_serial
  assert_eq(configure_quantities(ledger, amounts), Err(ResourceParked))
  assert_eq(mark_quantities_uncertain(ledger, send), Err(ResourceParked))
  assert_eq(
    observe_quantities(ledger, send, tokens=Some(14L)),
    Err(ResourceParked),
  )
  assert_eq(quantity_usage(ledger).uncertain, amounts)
  assert_eq(quantity_usage(ledger).consumed, zero_quantities())
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(settle_funded_read(claim, false), Err(Resource(ResourceParked)))
  assert_true(
    consumer.claim is Some(_) &&
    original_resource_park_current(park, origin) is Some(_),
  )
  // The producer still owns the actual 14-token observation. After confirmed
  // invalidation it retries that original fact; an overrun is recorded, not
  // discarded by the previous ResourceParked error or reset to a new envelope.
  assert_eq(retire_original_resource_park(park), Err(CleanupPending))
  resource_park_test_invalidate(park)
  assert_eq(observe_quantities(ledger, send, tokens=Some(14L)), Err(TokenLimit))
  assert_eq(quantity_usage(ledger).consumed.tokens, 14L)
  assert_eq(quantity_usage(ledger).uncertain.cost_units, 17L)
  assert_eq(quantity_usage(ledger).uncertain.duration_ms, 19L)
  assert_eq(ledger.next_capacity_serial, serial)
  settle_reservation(ledger, send).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  assert_eq(quantity_usage(ledger).consumed.tokens, 14L)
}
