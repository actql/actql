///|
fn original_comparison_finish(
  value : OriginalStateComparison[OriginalReadTestOrigin],
  quantum : Int,
) -> Int raise {
  let mut total = 0
  for _ in 0..<10 {
    match advance_original_state_comparison(value, quantum) {
      ComparisonContinue(work=n) => total += n
      ComparisonComplete(work=n) => return total + n
      ComparisonFailed(_, ..) => fail("original comparison unexpectedly failed")
    }
  }
  fail("original comparison exceeded its independent three-step bound")
}

///|
test "original state comparison rejects unwritten reading and pending exact writer phases" {
  let document = original_match_document(original_document_test_wire(), 1, 0, 0)
  let (ledger, identity, origin) = original_state_write_fixture(17)
  // Precharging an equal snapshot is not completion of the exact Writer.
  charge_planning(ledger, 17).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  assert_true(document.state == claim.admitted)
  assert_true(funded_read_available(claim, origin))
  assert_true(claim.phase is Reading)
  assert_true(
    start_original_state_comparison(claim, origin, document, 3)
    is Err(Original(ChangedOriginalState)),
  )
  assert_true(
    original_state_document_block_matches(claim, origin, document, 0)
    is Err(ChangedOriginalState),
  )
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  let (pending_ledger, pending_identity, pending_origin) = original_state_write_fixture(
    17,
  )
  let encoder = @encode.writer(1000, 200, 10)
  let (pending, writer) = prepare_original_state_write(
    pending_identity, pending_origin, encoder, 7L, 5L,
  ).unwrap()
  assert_true(document.state == pending.admitted)
  assert_true(
    advance_original_state_write(writer, 1) is StateWriteContinue(work=1),
  )
  assert_true(
    start_original_state_comparison(pending, pending_origin, document, 3)
    is Err(Original(ChangedOriginalState)),
  )
  assert_true(
    original_state_document_block_matches(pending, pending_origin, document, 0)
    is Err(ChangedOriginalState),
  )
  assert_true(settle_funded_read(pending, false) is Err(CleanupPending))
  assert_true(pending.phase is Stopping)
  assert_true(writer.claim is None && writer.writer is None)
  assert_true(document.source is Some(_))
  assert_eq(ledger_usage(pending_ledger).reserved_retention_bytes, 10L)
  assert_true(
    start_original_state_comparison(pending, pending_origin, document, 3)
    is Err(Original(ChangedOriginalState)),
  )
  settle_funded_read(pending, true).unwrap()
  assert_true(finish_original_ledger_inventory(pending_ledger, true).unwrap())
  assert_eq(ledger_usage(pending_ledger).planning_work, 17)
  retire_original_state_document(document)
}

///|
test "original state comparison retires its borrows when same claim enters consumer" {
  let (ledger, claim, origin) = original_match_live_read()
  let document = original_match_document(original_document_test_wire(), 1, 0, 0)
  let compare = start_original_state_comparison(claim, origin, document, 3).unwrap()
  assert_true(
    advance_original_state_comparison(compare, 1) is ComparisonContinue(work=1),
  )
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  assert_true(
    advance_original_state_comparison(compare, 1)
    is ComparisonFailed(Original(ChangedOriginalState), work=1),
  )
  assert_true(
    compare.claim is None && compare.origin is None && compare.document is None,
  )
  assert_true(document.source is Some(_))
  assert_true(
    consumer.claim is Some(original) && physical_equal(original, claim),
  )
  assert_true(
    settle_funded_read_consumer(consumer, false) is Err(CleanupPending),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(consumer.claim is Some(_))
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(consumer.claim is None)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(ledger_usage(ledger).planning_work, 17)
  retire_original_state_document(document)
}

///|
test "original state comparison complete inventory is quantum invariant and keeps same Ledger custody" {
  for quantum in [1, 2, 10] {
    let (ledger, claim, origin) = original_match_live_read()
    let document = original_match_document(
      original_document_test_wire(),
      1,
      0,
      0,
    )
    let before = ledger_usage(ledger)
    assert_true(
      start_original_state_comparison(claim, origin, document, 2)
      is Err(WorkLimit),
    )
    let value = start_original_state_comparison(claim, origin, document, 3).unwrap()
    assert_eq(original_comparison_finish(value, quantum), 3)
    assert_eq(ledger_usage(ledger), before)
    assert_true(document.source is Some(_))
    assert_true(funded_read_available(claim, origin))
    assert_true(value.claim is None && value.document is None)
    assert_true(
      advance_original_state_comparison(value, 1)
      is ComparisonFailed(Terminal, work=0),
    )
    let handed = handoff_funded_read(claim, origin).unwrap()
    assert_true(physical_equal(handed, ledger))
    retire_original_state_document(document)
    settle_funded_read(claim, true).unwrap()
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  }
}

///|
test "original state comparison catches late record mismatch without publishing partial match" {
  let (ledger, claim, origin) = original_match_live_read()
  let wire = original_document_test_wire().replace(
    old="\"-2\",\"0\",\"7\",\"5\"",
    new="\"-3\",\"0\",\"7\",\"5\"",
  )
  let document = original_match_document(wire, 1, 0, 0)
  let before = ledger_usage(ledger)
  let value = start_original_state_comparison(claim, origin, document, 3).unwrap()
  assert_true(
    advance_original_state_comparison(value, 1) is ComparisonContinue(work=1),
  )
  assert_true(
    advance_original_state_comparison(value, 1)
    is ComparisonFailed(RecordMismatch, work=1),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(document.source is Some(_))
  assert_true(funded_read_available(claim, origin))
  assert_true(value.claim is None && value.document is None)
  retire_original_state_document(document)
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original state comparison final check rejects mutation after all saved records" {
  let (ledger, claim, origin) = original_match_live_read()
  let document = original_match_document(original_document_test_wire(), 1, 0, 0)
  let value = start_original_state_comparison(claim, origin, document, 3).unwrap()
  assert_true(
    advance_original_state_comparison(value, 2) is ComparisonContinue(work=2),
  )
  assert_true(settle_funded_read(claim, false) is Err(CleanupPending))
  assert_true(
    advance_original_state_comparison(value, 1)
    is ComparisonFailed(Original(ChangedOriginalState), work=1),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(document.source is Some(_))
  retire_original_state_document(document)
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original state comparison cancel and invalid quantum do not settle original reservations" {
  let (ledger, claim, origin) = original_match_live_read()
  let document = original_match_document(original_document_test_wire(), 1, 0, 0)
  let value = start_original_state_comparison(claim, origin, document, 3).unwrap()
  assert_true(
    advance_original_state_comparison(value, 0)
    is ComparisonFailed(InvalidQuantum, work=0),
  )
  assert_true(
    advance_original_state_comparison(value, 1) is ComparisonContinue(work=1),
  )
  cancel_original_state_comparison(value)
  assert_true(
    advance_original_state_comparison(value, 1)
    is ComparisonFailed(Terminal, work=0),
  )
  assert_true(document.source is Some(_))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(funded_read_available(claim, origin))
  retire_original_state_document(document)
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}
