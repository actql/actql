///|
test "completed current match issues only after exact independent comparison work" {
  for quantum in [1, 2, 3] {
    let (ledger, origin, _, consumer) = current_state_test_consumer(17)
    let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
    let document = current_document_test_read(current_document_test_wire())
    let cursor = start_original_current_state_comparison(
      park, origin, document, 3,
    ).unwrap()
    let before = ledger_usage(ledger)
    let serial = ledger.next_capacity_serial
    let mut work = 0
    let mut matched : OriginalCurrentStateMatch[OriginalReadTestOrigin]? = None
    for _ in 0..<3 {
      match
        advance_original_current_state_comparison_with_match(cursor, quantum) {
        CurrentMatchContinue(work=n) => {
          work += n
          assert_true(matched is None)
        }
        CurrentMatchComplete(value, work=n) => {
          work += n
          matched = Some(value)
          break
        }
        _ => abort("independent current match unexpectedly refused")
      }
    }
    assert_eq(work, 3)
    let value = matched.unwrap()
    assert_true(cursor.park is None && cursor.document is None)
    assert_true(
      original_current_state_match_current(value, park, origin) is Some(same) &&
      physical_equal(value, same),
    )
    assert_true(
      advance_original_current_state_comparison_with_match(cursor, 1)
      is CurrentMatchFailed(Terminal, work=0),
    )
    assert_eq(ledger_usage(ledger), before)
    assert_eq(ledger.next_capacity_serial, serial)
    assert_true(charge_planning(ledger, 1) is Err(ResourceParked))
    retire_original_current_state_match(value)
    assert_true(value.park is None && value.document is None)
    assert_true(
      original_current_state_match_current(value, park, origin) is None,
    )
    assert_true(document.source is Some(_))
    assert_true(original_resource_park_current(park, origin) is Some(_))
    retire_original_current_state_document(document)
    resource_park_test_invalidate(park)
    settle_funded_read_consumer(consumer, true).unwrap()
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
    retire_original_resource_park(park).unwrap()
  }
}

///|
test "completed current match refuses foreign origin park retired document and invalidated fence" {
  let (ledger, origin, _, consumer) = current_state_test_consumer(17)
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let (_, foreign, _, other_consumer) = current_state_test_consumer(17)
  let other = park_original_resource_consumer_for_state_write(
    other_consumer, foreign,
  ).unwrap()
  let document = current_document_test_read(current_document_test_wire())
  let cursor = start_original_current_state_comparison(
    park, origin, document, 3,
  ).unwrap()
  let value = match
    advance_original_current_state_comparison_with_match(cursor, 3) {
    CurrentMatchComplete(value, work=3) => value
    _ => abort("independent current match unexpectedly refused")
  }
  let before = ledger_usage(ledger)
  assert_true(
    original_current_state_match_current(value, other, origin) is None,
  )
  assert_true(
    original_current_state_match_current(value, park, foreign) is None,
  )
  assert_true(
    original_current_state_match_current(value, park, origin) is Some(_),
  )
  retire_original_current_state_document(document)
  assert_true(original_current_state_match_current(value, park, origin) is None)
  assert_eq(ledger_usage(ledger), before)
  retire_original_current_state_match(value)
  let live_document = current_document_test_read(current_document_test_wire())
  let live_cursor = start_original_current_state_comparison(
    park, origin, live_document, 3,
  ).unwrap()
  let live_match = match
    advance_original_current_state_comparison_with_match(live_cursor, 3) {
    CurrentMatchComplete(value, work=3) => value
    _ => abort("independent second current match unexpectedly refused")
  }
  resource_park_test_invalidate(park)
  assert_true(live_document.source is Some(_))
  assert_true(
    original_current_state_match_current(live_match, park, origin) is None,
  )
  retire_original_current_state_match(live_match)
  retire_original_current_state_document(live_document)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  assert_true(original_current_state_match_current(value, park, origin) is None)
}

///|
test "completed current match cannot promote cancelled mismatched or partially advanced data" {
  let (ledger, origin, _, consumer) = current_state_test_consumer(17)
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let document = current_document_test_read(current_document_test_wire())
  let cursor = start_original_current_state_comparison(
    park, origin, document, 3,
  ).unwrap()
  assert_true(
    advance_original_current_state_comparison_with_match(cursor, 0)
    is CurrentMatchFailed(InvalidQuantum, work=0),
  )
  assert_true(cursor.position == 0)
  assert_true(
    advance_original_current_state_comparison_with_match(cursor, 1)
    is CurrentMatchContinue(work=1),
  )
  cancel_original_current_state_comparison(cursor)
  assert_true(
    advance_original_current_state_comparison_with_match(cursor, 3)
    is CurrentMatchFailed(Terminal, work=0),
  )
  let wrong = current_document_test_read(
    current_document_test_wire().replace(old="\"-3\"", new="\"-4\""),
  )
  let mismatch = start_original_current_state_comparison(park, origin, wrong, 3).unwrap()
  assert_true(
    advance_original_current_state_comparison_with_match(mismatch, 3)
    is CurrentMatchFailed(RecordMismatch, work=1),
  )
  assert_true(mismatch.park is None && mismatch.document is None)
  retire_original_current_state_document(wrong)
  retire_original_current_state_document(document)
  resource_park_test_invalidate(park)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
}
