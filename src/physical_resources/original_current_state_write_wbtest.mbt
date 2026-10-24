///|
fn current_state_test_consumer(
  planning : Int,
) -> (
  Ledger,
  OriginalReadTestOrigin,
  FundedReadClaim[OriginalReadTestOrigin],
  FundedReadConsumer[OriginalReadTestOrigin],
) {
  let ledger = create_ledger({
    planning_work: planning,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 100L,
    retained_bytes: 256L,
    execution_bytes: 256L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let origin = original_read_test_origin()
  let (claim, consumer) = resource_park_test_consumer(identity, origin)
  (ledger, origin, claim, consumer)
}

///|
fn[T] finish_current_state_test_writer(
  value : OriginalCurrentStateWrite[T],
  quantum : Int,
) -> Int {
  for total = 0 {
    match advance_original_current_state_write(value, quantum) {
      StateWriteContinue(work~) => continue total + work
      StateWriteComplete(work~) => break total + work
      StateWriteFailed(_, ..) => break -1
    }
  }
}

///|
test "original current write fixes parked current bytes quantum and work independently" {
  // Independent sixteen container/header blocks plus the one existing read
  // record. No second appended read, descriptor, reservation or serial.
  let expected = "[\"actql-original-ledger-state/0.1\",[\"17\",\"16\",\"16\",\"100\",\"256\",\"256\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"4\",\"0\",\"0\",true,true,false,\"parked\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  for quantum in [1, 3, 17, 100] {
    let (ledger, origin, claim, consumer) = current_state_test_consumer(17)
    let admitted = claim.admitted
    let serial = ledger.next_capacity_serial
    let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
    let writer = @encode.writer(1000, 200, 10)
    let cursor = start_original_current_state_write(park, origin, writer).unwrap()
    let before = ledger_usage(ledger)
    assert_true(
      start_original_current_state_write(park, origin, writer)
      is Err(Original(SpentClaim)),
    )
    assert_eq(finish_current_state_test_writer(cursor, quantum), 17)
    assert_eq(@encode.finish(writer), expected)
    // Current-cut data must not be admitted as the initial immutable read.
    // Its dedicated matching Reader/Store authentication is a separate unit.
    assert_true(
      start_original_state_document_read(
        original_document_test_cursor(expected),
        4,
        0,
        0,
        100,
      )
      is Err(InvalidRecord),
    )
    assert_eq(ledger_usage(ledger), before)
    assert_eq(ledger.next_capacity_serial, serial)
    assert_true(claim.admitted == admitted)
    assert_true(original_resource_park_current(park, origin) is Some(_))
    assert_true(cursor.park is None && cursor.writer is None)
    assert_true(
      advance_original_current_state_write(cursor, 1)
      is StateWriteFailed(Terminal, work=0),
    )
    resource_park_test_invalidate(park)
    settle_funded_read_consumer(consumer, true).unwrap()
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
    retire_original_resource_park(park).unwrap()
  }
}

///|
test "original current write includes actual post-handoff capacity not initial admission" {
  // Two current records: original read (-2) and later Model capacity (-3).
  // Their 7/5 and 2/3 coexist with bootstrap 3/2. Eighteen logical blocks.
  let expected = "[\"actql-original-ledger-state/0.1\",[\"18\",\"16\",\"16\",\"100\",\"256\",\"256\"],[\"18\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"12\",\"10\",\"12\",\"0\",\"3\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-4\",\"0\",\"0\"],[\"4\",\"0\",\"0\",true,true,false,\"parked\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false],[\"-3\",\"0\",\"2\",\"3\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  let (ledger, origin, claim, consumer) = current_state_test_consumer(18)
  let admitted = claim.admitted
  let (_, model_capacity) = handoff_funded_read_consumer_capacity(
    consumer, origin, 2L, 3L,
  ).unwrap()
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let writer = @encode.writer(1000, 200, 10)
  let cursor = start_original_current_state_write(park, origin, writer).unwrap()
  assert_eq(finish_current_state_test_writer(cursor, 2), 18)
  assert_eq(@encode.finish(writer), expected)
  assert_true(
    claim.admitted == admitted && admitted.usage.reserved_retention_bytes == 10L,
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 12L)
  resource_park_test_invalidate(park)
  settle_capacity(ledger, model_capacity).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
}

///|
test "original current write hash matches independent parked bytes and exact byte ceiling" {
  // SHA-256 and 411 UTF-8 bytes of the preceding hand-written parked vector,
  // calculated independently with pinned Node crypto, not this encoder.
  let (ledger, origin, _, consumer) = current_state_test_consumer(17)
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let writer = @encode.hashing_writer(411, 200, 10)
  let cursor = start_original_current_state_write(park, origin, writer).unwrap()
  assert_eq(finish_current_state_test_writer(cursor, 1), 17)
  assert_eq(
    @encode.finish_hash(writer),
    "55faf2cb0f9a1fa0849911a4ae63ff91f27135ca91e50015ef00dcc27105c5ba",
  )
  resource_park_test_invalidate(park)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()

  let (ledger, origin, _, consumer) = current_state_test_consumer(17)
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let writer = @encode.hashing_writer(410, 200, 10)
  let cursor = start_original_current_state_write(park, origin, writer).unwrap()
  assert_eq(finish_current_state_test_writer(cursor, 1), -1)
  assert_true(cursor.park is None && cursor.writer is None)
  assert_eq(ledger_usage(ledger).planning_work, 17)
  assert_true(original_resource_park_current(park, origin) is Some(_))
  resource_park_test_invalidate(park)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
}

///|
test "original current write preserves the actual stopping phase without read restart" {
  let expected = "[\"actql-original-ledger-state/0.1\",[\"17\",\"16\",\"16\",\"100\",\"256\",\"256\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"4\",\"0\",\"0\",true,true,false,\"stopping\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  let (ledger, origin, claim, consumer) = current_state_test_consumer(17)
  let admitted = claim.admitted
  stop_funded_read_consumer(consumer).unwrap()
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let writer = @encode.writer(1000, 200, 10)
  let cursor = start_original_current_state_write(park, origin, writer).unwrap()
  assert_eq(finish_current_state_test_writer(cursor, 1), 17)
  assert_eq(@encode.finish(writer), expected)
  assert_true(
    claim.admitted == admitted && park.previous is Some(ConsumerStopping(_)),
  )
  resource_park_test_invalidate(park)
  assert_true(claim.phase is ConsumerStopping(_))
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
}

///|
test "original current write one-short foreign copied and unprepaid refuse without mutation" {
  let (ledger, origin, claim, consumer) = current_state_test_consumer(16)
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  assert_true(
    park_original_resource_consumer_for_state_write(consumer, origin)
    is Err(Resource(PlanningLimit)),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_true(
    ledger.original_inventory.unwrap().park is None &&
    claim.phase is ConsumerStarted(_),
  )
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let writer = @encode.writer(1000, 200, 10)
  assert_true(
    start_original_current_state_write(park, origin, writer)
    is Err(Original(SpentClaim)),
  )
  assert_eq(@encode.writer_progress(writer), (0, 0, 0))
  assert_eq(ledger_usage(ledger), before)
  resource_park_test_invalidate(park)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  @encode.cancel_writer(writer)

  let (ledger, origin, _, consumer) = current_state_test_consumer(17)
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let copy : OriginalResourcePark[OriginalReadTestOrigin] = {
    consumer: park.consumer,
    origin: park.origin,
    fence: park.fence,
    previous: park.previous,
    state_write_work: park.state_write_work,
    invalidation: park.invalidation,
  }
  let writer = @encode.writer(1000, 200, 10)
  assert_true(
    start_original_current_state_write(copy, origin, writer)
    is Err(Original(ChangedOriginalState)),
  )
  assert_true(
    start_original_current_state_write(
      park,
      original_read_test_origin(),
      writer,
    )
    is Err(Original(ChangedOriginalState)),
  )
  assert_eq(park.state_write_work, Some(17))
  assert_eq(@encode.writer_progress(writer), (0, 0, 0))
  let cursor = start_original_current_state_write(park, origin, writer).unwrap()
  cancel_original_current_state_write(cursor)
  resource_park_test_invalidate(park)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  retire_original_resource_park(copy).unwrap()
}

///|
test "original current write partial cancel encoding failure and stale park retain custody" {
  for cancel in [true, false] {
    let (ledger, origin, _, consumer) = current_state_test_consumer(17)
    stop_funded_read_consumer(consumer).unwrap()
    let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
    let writer = @encode.writer(if cancel { 1000 } else { 1 }, 200, 10)
    let cursor = start_original_current_state_write(park, origin, writer).unwrap()
    let before = ledger_usage(ledger)
    if cancel {
      assert_true(
        advance_original_current_state_write(cursor, 1)
        is StateWriteContinue(work=1),
      )
      cancel_original_current_state_write(cursor)
    } else {
      assert_true(
        advance_original_current_state_write(cursor, 1)
        is StateWriteFailed(Encoding, work=1),
      )
    }
    assert_true(cursor.park is None && cursor.writer is None)
    assert_eq(ledger_usage(ledger), before)
    assert_eq(
      stop_funded_read_consumer(consumer),
      Err(Resource(ResourceParked)),
    )
    assert_true(original_resource_park_current(park, origin) is Some(_))
    assert_true(
      settle_funded_read_consumer(consumer, false)
      is Err(Resource(ResourceParked)),
    )
    resource_park_test_invalidate(park)
    settle_funded_read_consumer(consumer, true).unwrap()
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
    retire_original_resource_park(park).unwrap()
  }
  let (ledger, origin, _, consumer) = current_state_test_consumer(17)
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let writer = @encode.writer(1000, 200, 10)
  let cursor = start_original_current_state_write(park, origin, writer).unwrap()
  assert_true(
    advance_original_current_state_write(cursor, 1)
    is StateWriteContinue(work=1),
  )
  resource_park_test_invalidate(park)
  assert_true(
    advance_original_current_state_write(cursor, 1)
    is StateWriteFailed(Original(ChangedOriginalState), work=0),
  )
  assert_true(cursor.park is None && cursor.writer is None)
  assert_eq(ledger_usage(ledger).planning_work, 17)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
}
