///|
test "current owned Reader uses original ceilings and counts without modifying its ledger" {
  let (ledger, origin, _, consumer) = current_state_test_consumer(17)
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  assert_eq(
    original_current_state_read_bounds(park, origin),
    Ok({
      max_reservations: 4,
      max_holdings: 0,
      max_delegations: 0,
      reservations: 1,
      holdings: 0,
      delegations: 0,
      reader_work: 3,
    }),
  )
  let source = original_document_test_cursor(current_document_test_wire())
  assert_true(
    start_original_current_state_document_read_for_park(
      park,
      origin,
      source,
      2,
      current_document_test_limits(),
    )
    is Err(Document(WorkLimit)),
  )
  let read = start_original_current_state_document_read_for_park(
    park,
    origin,
    source,
    3,
    current_document_test_limits(),
  ).unwrap()
  let document = match advance_original_current_state_document_read(read, 3) {
    CurrentDocumentComplete(value, work=3) => value
    _ => abort("original-bounded current Reader failed")
  }
  let comparison = start_original_current_state_comparison(
    park, origin, document, 3,
  ).unwrap()
  assert_true(
    advance_original_current_state_comparison(comparison, 3)
    is ComparisonComplete(work=3),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  retire_original_current_state_document(document)
  resource_park_test_invalidate(park)
  assert_true(
    original_current_state_read_bounds(park, origin)
    is Err(ChangedOriginalState),
  )
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  assert_true(
    original_current_state_read_bounds(park, origin)
    is Err(ChangedOriginalState),
  )
}

///|
test "current owned Reader rejects packet ceilings or incomplete census without a partial borrow" {
  let (ledger, origin, _, consumer) = current_state_test_consumer(17)
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let before = ledger_usage(ledger)
  let original = current_document_test_wire()
  for
    changed in [
      original.replace(
        old="[\"4\",\"0\",\"0\",true",
        new="[\"3\",\"0\",\"0\",true",
      ),
      original.replace(
        old="[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]]",
        new="[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false],[\"0\",\"0\",\"0\",\"0\",true,false,null,null,[false,false,false],null,false,false]]",
      ),
    ] {
    let source = original_document_test_cursor(changed)
    assert_true(
      start_original_current_state_document_read_for_park(
        park,
        origin,
        source,
        4,
        current_document_test_limits(),
      )
      is Err(Document(InvalidRecord)),
    )
    assert_true(@decode.array_length(source) is Some(12))
    assert_eq(ledger_usage(ledger), before)
  }
  let foreign = original_read_test_origin()
  assert_true(
    original_current_state_read_bounds(park, foreign) is Err(ForeignOrigin),
  )
  assert_true(
    start_original_current_state_document_read_for_park(
      park,
      foreign,
      original_document_test_cursor(original),
      3,
      current_document_test_limits(),
    )
    is Err(Original(ForeignOrigin)),
  )
  resource_park_test_invalidate(park)
  assert_true(
    start_original_current_state_document_read_for_park(
      park,
      origin,
      original_document_test_cursor(original),
      3,
      current_document_test_limits(),
    )
    is Err(Original(ChangedOriginalState)),
  )
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
}
