///|
fn original_state_write_fixture(
  planning : Int,
  retained? : Int64 = 10L,
  execution? : Int64 = 7L,
  census? : Int = 1,
) -> (Ledger, OriginalLedgerIdentity, OriginalReadTestOrigin) {
  let ledger = create_ledger({
    planning_work: planning,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: retained,
    execution_bytes: execution,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(
    ledger, bootstrap, census, 0, 0,
  ).unwrap()
  let origin = original_read_test_origin()
  (ledger, identity, origin)
}

///|
fn[T] finish_original_state_test_writer(
  cursor : OriginalStateWrite[T],
  quantum : Int,
) -> Int {
  for total = 0 {
    match advance_original_state_write(cursor, quantum) {
      StateWriteContinue(work~) => continue total + work
      StateWriteComplete(work~) => break total + work
      StateWriteFailed(_, ..) => break -1
    }
  }
}

///|
test "original one-shot write exact claim routing refuses foreign origin without retirement" {
  let (ledger, identity, origin) = original_state_write_fixture(17)
  let foreign = original_read_test_origin()
  let writer = @encode.writer(1000, 200, 10)
  let (claim, cursor) = prepare_original_state_write(
    identity, origin, writer, 7L, 5L,
  ).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    advance_funded_read_state_write(claim, foreign, 1)
    is StateWriteFailed(Original(ForeignOrigin), work=0),
  )
  assert_eq(@encode.writer_progress(writer), (0, 0, 0))
  assert_eq(ledger_usage(ledger), before)
  assert_true(cursor.claim is Some(current) && physical_equal(current, claim))
  assert_true(
    advance_funded_read_state_write(claim, origin, 0)
    is StateWriteFailed(InvalidQuantum, work=0),
  )
  assert_eq(finish_original_state_test_writer(cursor, 1), 17)
  assert_true(
    advance_funded_read_state_write(claim, origin, 1)
    is StateWriteFailed(Terminal, work=0),
  )
  assert_true(funded_read_available(claim, origin))
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original one-shot write independently fixes exact bytes work and quantum" {
  // Hand-written field order and original identities; never derive this from
  // product output. Strings preserve decimal Int64 exactly on every backend.
  let expected = "[\"actql-original-ledger-state/0.1\",[\"17\",\"2\",\"3\",\"11\",\"10\",\"7\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"1\",\"0\",\"0\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  for quantum in [1, 3, 17, 100] {
    let (ledger, identity, origin) = original_state_write_fixture(17)
    let writer = @encode.writer(1000, 200, 10)
    let (claim, cursor) = prepare_original_state_write(
      identity, origin, writer, 7L, 5L,
    ).unwrap()
    // Fixed seventeen blocks: nine header/state, eight container/read/close.
    assert_true(handoff_funded_read(claim, origin) is Err(SpentClaim))
    assert_true(settle_funded_read(claim, true) is Err(CleanupPending))
    assert_eq(finish_original_state_test_writer(cursor, quantum), 17)
    assert_eq(@encode.finish(writer), expected)
    assert_eq(ledger_usage(ledger).planning_work, 17)
    assert_true(funded_read_available(claim, origin))
    assert_true(
      prepare_original_state_write(identity, origin, writer, 7L, 5L)
      is Err(Original(SpentClaim)),
    )
    assert_true(
      advance_original_state_write(cursor, 1)
      is StateWriteFailed(Terminal, work=0),
    )
    handoff_funded_read(claim, origin).unwrap() |> ignore
    settle_funded_read(claim, true).unwrap()
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  }
}

///|
test "original one-shot write one-short fails before output without a fresh budget" {
  let (ledger, identity, origin) = original_state_write_fixture(16)
  let before = ledger_usage(ledger)
  let writer = @encode.writer(1000, 200, 10)
  assert_true(
    prepare_original_state_write(identity, origin, writer, 7L, 5L)
    is Err(Resource(PlanningLimit)),
  )
  assert_eq(@encode.writer_progress(writer), (0, 0, 0))
  assert_eq(ledger_usage(ledger), before)
  assert_false(ledger.original_inventory.unwrap().descriptor_issued)
  assert_false(ledger.original_inventory.unwrap().read_claimed)
  @encode.cancel_writer(writer)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original one-shot write hash matches independent golden bytes" {
  let (ledger, identity, origin) = original_state_write_fixture(17)
  let writer = @encode.hashing_writer(406, 200, 10)
  let (claim, cursor) = prepare_original_state_write(
    identity, origin, writer, 7L, 5L,
  ).unwrap()
  assert_eq(finish_original_state_test_writer(cursor, 3), 17)
  // SHA256 of the preceding hand-written 406-byte fixture, calculated with
  // an independent Node crypto implementation, not this product writer.
  assert_eq(
    @encode.finish_hash(writer),
    "7ed6db2394d7eaa87d65b022a6bc78f722efaf7a0293115de52c09a89893aae9",
  )
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original one-shot write includes unknown observed spent serial and cleanup custody" {
  let ledger = create_ledger({
    planning_work: 19,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 10L,
    execution_bytes: 7L,
  }).unwrap()
  let amounts : QuantityAmounts = {
    tokens: 9223372036854775807L,
    cost_units: 17L,
    duration_ms: 19L,
  }
  configure_quantities(ledger, amounts).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 3, 0, 0).unwrap()
  let attempt = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  mark_quantities_uncertain(ledger, attempt).unwrap()
  observe_quantities(ledger, attempt, cost_units=Some(7L)).unwrap()
  // The existing observer releases the cost envelope (17) and records actual
  // cost (7); the per-token unknown cost is now zero, not seventeen or seven.
  assert_eq(attempt.uncertain_quantities, Some({ ..amounts, cost_units: 0L, }))
  mark_cleanup_pending(ledger, attempt).unwrap()
  let spent = reserve_capacity(ledger, 0L, 0L).unwrap()
  settle_capacity(ledger, spent).unwrap()
  let origin = original_read_test_origin()
  let writer = @encode.writer(2000, 300, 10)
  let (claim, cursor) = prepare_original_state_write(
    identity, origin, writer, 7L, 5L,
  ).unwrap()
  assert_eq(finish_original_state_test_writer(cursor, 2), 18)
  let expected = "[\"actql-original-ledger-state/0.1\",[\"19\",\"2\",\"3\",\"11\",\"10\",\"7\"],[\"18\",\"1\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"3\",\"0\"],[\"0\",\"0\",\"0\"],[\"9223372036854775807\",\"17\",\"19\"],[[\"0\",\"0\",\"0\"],[\"9223372036854775807\",\"0\",\"19\"],[\"0\",\"7\",\"0\"]],[\"-4\",\"1\",\"0\"],[\"3\",\"0\",\"0\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"0\",\"0\",\"0\",\"0\",true,true,null,[\"9223372036854775807\",\"0\",\"19\"],[false,true,false],null,false,true],[\"-3\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  assert_eq(@encode.finish(writer), expected)
  assert_true(reservation_pending(attempt))
  assert_eq(ledger.next_capacity_serial, Some(-4))
  settle_funded_read(claim, true).unwrap()
  assert_true(!finish_original_ledger_inventory(ledger, true).unwrap())
  settle_reservation(ledger, attempt).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(quantity_usage(ledger).uncertain.tokens, 9223372036854775807L)
}

///|
test "original one-shot write cancellation encoding failure and foreign mutation preserve read cleanup" {
  for mode in [0, 1, 2] {
    let (ledger, identity, origin) = original_state_write_fixture(18)
    let writer = @encode.writer(if mode == 1 { 5 } else { 1000 }, 200, 10)
    let (claim, cursor) = prepare_original_state_write(
      identity, origin, writer, 7L, 5L,
    ).unwrap()
    if mode == 0 {
      assert_true(
        advance_original_state_write(cursor, 1) is StateWriteContinue(work=1),
      )
      cancel_original_state_write(cursor)
      assert_true(
        cursor.claim is None && cursor.origin is None && cursor.writer is None,
      )
      assert_true(
        advance_original_state_write(cursor, 1)
        is StateWriteFailed(Terminal, work=0),
      )
    } else if mode == 1 {
      assert_true(
        advance_original_state_write(cursor, 1)
        is StateWriteFailed(Encoding, work=1),
      )
    } else {
      charge_planning(ledger, 1).unwrap()
      assert_true(
        advance_original_state_write(cursor, 1)
        is StateWriteFailed(Original(ChangedOriginalState), work=0),
      )
    }
    assert_true(capacity_reservation_open(claim.read))
    assert_true(capacity_reservation_open(claim.descriptor.bootstrap))
    assert_true(settle_funded_read(claim, false) is Err(CleanupPending))
    assert_eq(ledger_usage(ledger).reserved_retention_bytes, 10L)
    settle_funded_read(claim, true).unwrap()
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
    assert_true(settle_funded_read(claim, true) is Err(SpentClaim))
    assert_true(ledger_usage(ledger).planning_work >= 17)
  }
}

///|
test "original one-shot write preserves live output holding delegation and exact inventory work" {
  let ledger = create_ledger({
    planning_work: 22,
    attempts: 5,
    holdings: 5,
    transfer_bytes: 11L,
    retained_bytes: 20L,
    execution_bytes: 10L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 3, 1, 1).unwrap()
  let send = reserve_attempt(ledger, 1L, 4L, 1L).unwrap()
  let held = retain_allocation(ledger, send, 2L).unwrap()
  settle_completed_output_reservation(ledger, send, Some(held), 2L, 1L).unwrap()
  let delegation = reserve_execution_delegation(
    ledger,
    {
      planning_work: 1,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 2L,
      retained_bytes: 2L,
      execution_bytes: 1L,
    },
    2L,
    1L,
  ).unwrap()
  let origin = original_read_test_origin()
  let writer = @encode.writer(2000, 300, 10)
  let (claim, cursor) = prepare_original_state_write(
    identity, origin, writer, 7L, 5L,
  ).unwrap()
  // 17 fixed blocks + 2 original reservations + 1 holding + 1 delegation.
  assert_eq(finish_original_state_test_writer(cursor, 1), 21)
  let expected = "[\"actql-original-ledger-state/0.1\",[\"22\",\"5\",\"5\",\"11\",\"20\",\"10\"],[\"21\",\"0\",\"1\",\"0\",\"0\",\"2\",\"2\",\"12\",\"9\",\"14\",\"2\",\"4\",\"1\"],[\"1\",\"1\",\"1\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"2\",\"1\"],[\"3\",\"1\",\"1\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"0\",\"0\",\"0\",\"1\",true,true,null,null,[false,false,false],[\"0\",\"2\",\"1\"],true,false],[\"1\",\"2\",\"2\",\"1\",true,false,null,null,[false,false,false],null,true,false],[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[[\"0\",\"0\",\"2\",true]],[[\"1\",[\"1\",\"1\",\"1\",\"2\",\"2\",\"1\"],[\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\"]]]]"
  assert_eq(@encode.finish(writer), expected)
  assert_eq(ledger_usage(ledger).planning_work, 21)
  assert_eq(ledger_admission_limits(ledger).planning_work, 21)
  settle_funded_read(claim, true).unwrap()
  assert_true(!finish_original_ledger_inventory(ledger, true).unwrap())
  settle_reservation(ledger, send).unwrap()
  settle_execution_delegation(ledger, delegation, None).unwrap()
  assert_true(!finish_original_ledger_inventory(ledger, true).unwrap())
  release_allocation(ledger, held).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original one-shot write completes before the same early consumer and ledger handoff" {
  let (ledger, identity, origin) = original_state_write_fixture(
    17,
    retained=20L,
    execution=12L,
    census=2,
  )
  let writer = @encode.writer(1000, 200, 10)
  let (claim, cursor) = prepare_original_state_write(
    identity, origin, writer, 7L, 5L,
  ).unwrap()
  let admitted = claim.admitted
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  assert_true(
    claim.phase is Writing(current) && physical_equal(current, cursor),
  )
  assert_false(funded_read_available(claim, origin))
  assert_true(
    claim_funded_read_preparation(claim, origin, 7L, 5L) is Err(SpentClaim),
  )
  assert_true(
    handoff_funded_read_capacity(claim, origin, 10L, 5L) is Err(SpentClaim),
  )
  assert_true(settle_funded_read(claim, true) is Err(CleanupPending))
  assert_true(
    prepare_original_state_write(identity, origin, writer, 7L, 5L)
    is Err(Original(SpentClaim)),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(finish_original_state_test_writer(cursor, 1), 17)
  assert_true(claim.phase is Written)
  assert_true(claim.admitted == admitted)
  assert_true(
    cursor.claim is None && cursor.origin is None && cursor.writer is None,
  )
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  assert_true(
    claim_funded_read_preparation(claim, origin, 7L, 5L) is Err(SpentClaim),
  )
  enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  let (same, capacity) = handoff_funded_read_consumer_capacity(
    consumer, origin, 10L, 5L,
  ).unwrap()
  assert_true(physical_equal(same, ledger))
  assert_eq(ledger_usage(same).planning_work, 17)
  assert_true(
    settle_funded_read_consumer(consumer, false) is Err(CleanupPending),
  )
  assert_eq(ledger_usage(same).reserved_retention_bytes, 20L)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(consumer.claim is None)
  assert_false(finish_funded_read_inventory(claim, origin, true).unwrap())
  settle_capacity(same, capacity).unwrap()
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
  assert_eq(ledger_usage(same).planning_work, 17)
}

///|
test "original one-shot write rejects a foreign cursor without cancelling the real writer" {
  let (ledger, identity, origin) = original_state_write_fixture(17)
  let writer = @encode.writer(1000, 200, 10)
  let (claim, cursor) = prepare_original_state_write(
    identity, origin, writer, 7L, 5L,
  ).unwrap()
  // Opaque construction is not a public operation. White-box forgery must not
  // release a borrowed Writer belonging to the exact issued cursor.
  let foreign : OriginalStateWrite[OriginalReadTestOrigin] = {
    claim: cursor.claim,
    origin: cursor.origin,
    writer: cursor.writer,
    state: cursor.state,
    bounds: cursor.bounds,
    total: cursor.total,
    position: 0,
    terminal: false,
  }
  assert_true(
    advance_original_state_write(foreign, 1)
    is StateWriteFailed(Original(ChangedOriginalState), work=0),
  )
  assert_true(
    foreign.claim is None && foreign.origin is None && foreign.writer is None,
  )
  assert_true(
    claim.phase is Writing(current) && physical_equal(current, cursor),
  )
  assert_eq(finish_original_state_test_writer(cursor, 3), 17)
  assert_true(claim.phase is Written)
  assert_true(@encode.finish(writer).length() > 0)
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
  assert_eq(ledger_usage(ledger).planning_work, 17)
}

///|
test "original one-shot write failed read admission keeps spent work and original bootstrap" {
  let (ledger, identity, origin) = original_state_write_fixture(17, retained=9L)
  let writer = @encode.writer(1000, 200, 10)
  assert_true(
    prepare_original_state_write(identity, origin, writer, 7L, 5L)
    is Err(Original(Resource(RetentionLimit))),
  )
  assert_eq(@encode.writer_progress(writer), (0, 0, 0))
  assert_eq(ledger_usage(ledger).planning_work, 17)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 3L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 2L)
  assert_eq(ledger.next_capacity_serial, Some(-2))
  let inventory = ledger.original_inventory.unwrap()
  assert_true(inventory.descriptor_issued)
  assert_false(inventory.read_claimed)
  assert_eq(inventory.reservations.length(), 0)
  assert_true(capacity_reservation_open(identity.bootstrap))
  assert_true(
    prepare_original_state_write(identity, origin, writer, 7L, 5L)
    is Err(Original(SpentClaim)),
  )
  assert_eq(ledger_usage(ledger).planning_work, 17)
  @encode.cancel_writer(writer)
  assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
  assert_true(capacity_reservation_open(identity.bootstrap))
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(ledger_usage(ledger).planning_work, 17)
}
