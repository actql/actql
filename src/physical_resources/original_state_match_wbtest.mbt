///|
fn original_match_document(
  wire : String,
  n : Int,
  h : Int,
  d : Int,
) -> OriginalStateDocument {
  finish_document_test_read(
    start_original_state_document_read(
      original_document_test_cursor(wire),
      n,
      h,
      d,
      2 + n + h + d,
    ).unwrap(),
    1,
  ).0
}

///|
fn original_match_live_read() -> (
  Ledger,
  FundedReadClaim[OriginalReadTestOrigin],
  OriginalReadTestOrigin,
) raise {
  let (ledger, identity, origin) = original_state_write_fixture(17)
  let writer = @encode.writer(1000, 200, 10)
  let (claim, cursor) = prepare_original_state_write(
    identity, origin, writer, 7L, 5L,
  ).unwrap()
  assert_eq(finish_original_state_test_writer(cursor, 1), 17)
  @encode.finish(writer) |> ignore
  (ledger, claim, origin)
}

///|
test "original state matching compares independent bytes without creating resource authority" {
  let (ledger, claim, origin) = original_match_live_read()
  let document = original_match_document(original_document_test_wire(), 1, 0, 0)
  let before = ledger_usage(ledger)
  for block in [0, 1] {
    assert_eq(
      original_state_document_block_matches(claim, origin, document, block),
      Ok(true),
    )
  }
  for block in [-1, 2, 2147483647] {
    assert_true(
      original_state_document_block_matches(claim, origin, document, block)
      is Err(IncompleteInventory),
    )
  }
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, Some(-3))
  assert_true(funded_read_available(claim, origin))
  retire_original_state_document(document)
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original state matching rejects swapped per-token allocations despite identical aggregate" {
  let (ledger, claim, origin) = original_match_live_read()
  // The sum remains retention10/execution7. Neither aggregate reveals that
  // a bootstrap byte was assigned to a different original reservation.
  let wire = original_document_test_wire()
    .replace(old="\"-1\",\"0\",\"3\",\"2\"", new="\"-1\",\"0\",\"4\",\"2\"")
    .replace(old="\"-2\",\"0\",\"7\",\"5\"", new="\"-2\",\"0\",\"6\",\"5\"")
  let document = original_match_document(wire, 1, 0, 0)
  assert_true(document.state == claim.admitted)
  for block in [0, 1] {
    assert_eq(
      original_state_document_block_matches(claim, origin, document, block),
      Ok(false),
    )
  }
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(funded_read_available(claim, origin))
  retire_original_state_document(document)
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original state matching preserves original origin pending cleanup and retirement" {
  let (ledger, claim, origin) = original_match_live_read()
  let document = original_match_document(original_document_test_wire(), 1, 0, 0)
  assert_true(
    original_state_document_block_matches(
      claim,
      original_read_test_origin(),
      document,
      0,
    )
    is Err(ChangedOriginalState),
  )
  assert_true(settle_funded_read(claim, false) is Err(CleanupPending))
  assert_true(
    original_state_document_block_matches(claim, origin, document, 0)
    is Err(ChangedOriginalState),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(document.source is Some(_)) // no false physical cleanup
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(
    original_state_document_block_matches(claim, origin, document, 1)
    is Err(ChangedOriginalState),
  )
  retire_original_state_document(document)
  assert_true(document.source is None)
}

///|
test "original state matching refuses retired document and changed saved usage" {
  let (ledger, claim, origin) = original_match_live_read()
  let wire = original_document_test_wire().replace(
    old="[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\"",
    new="[\"16\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\"",
  )
  let document = original_match_document(wire, 1, 0, 0)
  assert_eq(
    original_state_document_block_matches(claim, origin, document, 0),
    Ok(false),
  )
  assert_eq(ledger_usage(ledger).planning_work, 17)
  retire_original_state_document(document)
  assert_true(
    original_state_document_block_matches(claim, origin, document, 0)
    is Err(ChangedOriginalState),
  )
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
fn original_match_full_wire() -> String {
  // Independent record order and issuer serials from the saved contract.
  "[\"actql-original-ledger-state/0.1\",[\"26\",\"5\",\"5\",\"11\",\"20\",\"10\"],[\"21\",\"0\",\"1\",\"0\",\"0\",\"2\",\"2\",\"12\",\"9\",\"14\",\"2\",\"4\",\"1\"],[\"1\",\"1\",\"1\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"2\",\"1\"],[\"3\",\"1\",\"1\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"0\",\"0\",\"0\",\"1\",true,true,null,null,[false,false,false],[\"0\",\"2\",\"1\"],true,false],[\"1\",\"2\",\"2\",\"1\",true,false,null,null,[false,false,false],null,true,false],[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[[\"0\",\"0\",\"2\",true]],[[\"1\",[\"1\",\"1\",\"1\",\"2\",\"2\",\"1\"],[\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\"]]]]"
}

///|
test "original state matching rejects different census ceilings despite identical live records" {
  let (ledger, claim, origin) = original_match_live_read()
  let before = ledger_usage(ledger)
  for
    (replacement, n, h, d) in [
      ("[\"2\",\"0\",\"0\",true,true,false,\"reading\",true]", 2, 0, 0),
      ("[\"1\",\"1\",\"0\",true,true,false,\"reading\",true]", 1, 1, 0),
      ("[\"1\",\"0\",\"1\",true,true,false,\"reading\",true]", 1, 0, 1),
    ] {
    // Parsing against the saved ceilings is not authentication. All child
    // records, original usage and private serials are otherwise unchanged.
    let wire = original_document_test_wire().replace(
      old="[\"1\",\"0\",\"0\",true,true,false,\"reading\",true]",
      new=replacement,
    )
    let document = original_match_document(wire, n, h, d)
    assert_true(document.state == claim.admitted)
    assert_eq(document.counts, (1, 0, 0))
    for block in [0, 1] {
      assert_eq(
        original_state_document_block_matches(claim, origin, document, block),
        Ok(false),
      )
    }
    let compare = start_original_state_comparison(claim, origin, document, 3).unwrap()
    assert_true(
      advance_original_state_comparison(compare, 1)
      is ComparisonFailed(RecordMismatch, work=1),
    )
    assert_true(
      compare.claim is None &&
      compare.origin is None &&
      compare.document is None,
    )
    assert_true(
      document.source is Some(_) && funded_read_available(claim, origin),
    )
    assert_eq(ledger_usage(ledger), before)
    retire_original_state_document(document)
  }
  assert_eq(ledger.next_capacity_serial, Some(-3))
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original state matching checks original holdings delegations and completed output individually" {
  let ledger = create_ledger({
    planning_work: 26,
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
  assert_eq(finish_original_state_test_writer(cursor, 1), 21)
  assert_eq(@encode.finish(writer), original_match_full_wire())
  let document = original_match_document(original_match_full_wire(), 3, 1, 1)
  let before = ledger_usage(ledger)
  for block in 0..<6 {
    assert_eq(
      original_state_document_block_matches(claim, origin, document, block),
      Ok(true),
    )
  }
  for
    (old, replacement, block) in [
      ("[[\"0\",\"0\",\"2\",true]]", "[[\"1\",\"0\",\"2\",true]]", 4),
      ("[[\"0\",\"0\",\"2\",true]]", "[[\"0\",\"1\",\"2\",true]]", 4),
      ("[[\"0\",\"0\",\"2\",true]]", "[[\"0\",\"0\",\"3\",true]]", 4),
      ("[[\"0\",\"0\",\"2\",true]]", "[[\"0\",\"0\",\"2\",false]]", 4),
      (
        "[[\"1\",[\"1\",\"1\",\"1\",\"2\",\"2\",\"1\"]", "[[\"0\",[\"1\",\"1\",\"1\",\"2\",\"2\",\"1\"]",
        5,
      ),
      (
        "[[\"1\",[\"1\",\"1\",\"1\",\"2\",\"2\",\"1\"]", "[[\"1\",[\"2\",\"1\",\"1\",\"2\",\"2\",\"1\"]",
        5,
      ),
      (
        "[\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\"]]]]", "[\"1\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\"]]]]",
        5,
      ),
      (
        "[false,false,false],[\"0\",\"2\",\"1\"]", "[false,false,false],[\"1\",\"2\",\"1\"]",
        1,
      ),
    ] {
    let tampered = original_match_document(
      original_match_full_wire().replace(old~, new=replacement),
      3,
      1,
      1,
    )
    assert_true(tampered.state == claim.admitted)
    assert_eq(
      original_state_document_block_matches(claim, origin, tampered, block),
      Ok(false),
    )
    retire_original_state_document(tampered)
  }
  assert_eq(ledger_usage(ledger), before)
  retire_original_state_document(document)
  settle_funded_read(claim, true).unwrap()
  settle_reservation(ledger, send).unwrap()
  settle_execution_delegation(ledger, delegation, None).unwrap()
  release_allocation(ledger, held).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original state matching content equality is explicitly not original Store authentication" {
  let (first, first_claim, first_origin) = original_match_live_read()
  let (second, second_claim, second_origin) = original_match_live_read()
  assert_true(!physical_equal(first, second))
  let document = original_match_document(original_document_test_wire(), 1, 0, 0)
  // Identical record bytes can match two independently issued Ledgers. The
  // existing Store/Run/Entry/holding authentication is therefore mandatory;
  // this value comparison cannot issue a restored owner or a send grant.
  assert_eq(
    original_state_document_block_matches(
      first_claim, first_origin, document, 1,
    ),
    Ok(true),
  )
  assert_eq(
    original_state_document_block_matches(
      second_claim, second_origin, document, 1,
    ),
    Ok(true),
  )
  retire_original_state_document(document)
  settle_funded_read(first_claim, true).unwrap()
  settle_funded_read(second_claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(first, true).unwrap())
  assert_true(finish_original_ledger_inventory(second, true).unwrap())
}

///|
test "original state matching preserves unknown quantities spent serial and pending original attempt" {
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
  mark_cleanup_pending(ledger, attempt).unwrap()
  let spent = reserve_capacity(ledger, 0L, 0L).unwrap()
  settle_capacity(ledger, spent).unwrap()
  let origin = original_read_test_origin()
  let writer = @encode.writer(2000, 300, 10)
  let (claim, cursor) = prepare_original_state_write(
    identity, origin, writer, 7L, 5L,
  ).unwrap()
  assert_eq(finish_original_state_test_writer(cursor, 1), 18)
  // Authored existing decimal record contract, not output-derived expected data.
  let expected = "[\"actql-original-ledger-state/0.1\",[\"19\",\"2\",\"3\",\"11\",\"10\",\"7\"],[\"18\",\"1\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"3\",\"0\"],[\"0\",\"0\",\"0\"],[\"9223372036854775807\",\"17\",\"19\"],[[\"0\",\"0\",\"0\"],[\"9223372036854775807\",\"0\",\"19\"],[\"0\",\"7\",\"0\"]],[\"-4\",\"1\",\"0\"],[\"3\",\"0\",\"0\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"0\",\"0\",\"0\",\"0\",true,true,null,[\"9223372036854775807\",\"0\",\"19\"],[false,true,false],null,false,true],[\"-3\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  assert_eq(@encode.finish(writer), expected)
  let before = quantity_usage(ledger)
  let document = original_match_document(expected, 3, 0, 0)
  for block in 0..<3 {
    assert_eq(
      original_state_document_block_matches(claim, origin, document, block),
      Ok(true),
    )
  }
  for
    (old, changed, block) in [
      (
        "null,[\"9223372036854775807\",\"0\",\"19\"],[false,true,false]", "null,[\"9223372036854775807\",\"0\",\"18\"],[false,true,false]",
        1,
      ),
      (
        "[\"-3\",\"0\",\"7\",\"5\",true,false", "[\"-5\",\"0\",\"7\",\"5\",true,false",
        2,
      ),
    ] {
    let tampered = original_match_document(
      expected.replace(old~, new=changed),
      3,
      0,
      0,
    )
    assert_true(tampered.state == claim.admitted)
    assert_eq(
      original_state_document_block_matches(claim, origin, tampered, block),
      Ok(false),
    )
    retire_original_state_document(tampered)
  }
  assert_eq(quantity_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, Some(-4))
  assert_true(reservation_pending(attempt))
  retire_original_state_document(document)
  settle_funded_read(claim, true).unwrap()
  assert_true(!finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(reservation_pending(attempt))
  settle_reservation(ledger, attempt).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(quantity_usage(ledger), before)
}
