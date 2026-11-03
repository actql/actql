///|
fn original_captured_inputs_fixture(
  settled? : Bool = true,
) -> (Ledger, OriginalLedgerIdentity, Array[(Reservation, Holding)]) {
  // Independent lifetime amounts only, not a physical Model tariff.
  let ledger = create_ledger({
    planning_work: 10,
    attempts: 12,
    holdings: 8,
    transfer_bytes: 0L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 12, 8, 0).unwrap()
  let originals = []
  for _ in 0..<2 {
    let reservation = reserve_attempt(ledger, 0L, 1L, 1L).unwrap()
    let holding = retain_allocation(ledger, reservation, 1L).unwrap()
    if settled {
      settle_reservation(ledger, reservation).unwrap()
    }
    originals.push((reservation, holding))
  }
  (ledger, identity, originals)
}

///|
fn original_captured_inputs_release(
  ledger : Ledger,
  originals : Array[(Reservation, Holding)],
) -> Unit raise {
  for pair in originals {
    release_allocation(ledger, pair.1).unwrap()
    if reservation_open(pair.0) {
      settle_reservation(ledger, pair.0).unwrap()
    }
  }
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "plural capture census authenticates exact ordered originals without changing single input" {
  let (ledger, identity, originals) = original_captured_inputs_fixture()
  let (foreign, _, foreign_originals) = original_captured_inputs_fixture()
  let before = ledger_usage(ledger)
  assert_true(original_captured_inputs_prefix_available(ledger, originals))
  assert_true(
    original_ledger_captured_inputs_preparation_available(identity, originals),
  )
  assert_false(
    original_captured_prefix_available(ledger, originals[0].0, originals[0].1),
  )
  assert_false(original_ledger_captured_preparation_available(identity))
  for
    invalid in [
      [],
      [originals[0]],
      [originals[1], originals[0]],
      [originals[0], originals[0]],
      [foreign_originals[0], originals[1]],
      [(originals[0].0, foreign_originals[0].1), originals[1]],
      [(originals[0].0, originals[1].1), (originals[1].0, originals[0].1)],
    ] {
    assert_false(original_captured_inputs_prefix_available(ledger, invalid))
    assert_false(
      original_ledger_captured_inputs_preparation_available(identity, invalid),
    )
  }
  assert_false(original_captured_inputs_prefix_available(foreign, originals))
  assert_eq(ledger_usage(ledger), before)
  let prefix = reserve_attempt(ledger, 0L, 2L, 2L).unwrap()
  assert_true(
    original_captured_inputs_prefix_reservation_available(
      ledger, originals, prefix,
    ),
  )
  assert_true(
    original_ledger_captured_inputs_preparation_available(
      identity,
      originals,
      prefix=Some(prefix),
    ),
  )
  assert_false(
    original_captured_inputs_prefix_reservation_available(
      ledger,
      originals,
      originals[0].0,
    ),
  )
  assert_false(original_captured_inputs_prefix_available(ledger, originals))
  mark_cleanup_pending(ledger, prefix).unwrap()
  assert_false(
    original_captured_inputs_prefix_reservation_available(
      ledger, originals, prefix,
    ),
  )
  // No dependents does not acknowledge this pending prefix or its upstreams.
  assert_true(
    original_keyed_inputs_prefix_dependents_retired(ledger, originals, prefix),
  )
  assert_true(reservation_pending(prefix))
  assert_true(holding_available(ledger, originals[0].1))
  assert_true(holding_available(ledger, originals[1].1))
  settle_reservation(ledger, prefix).unwrap()
  assert_false(original_captured_inputs_prefix_available(ledger, originals))
  assert_eq(ledger.next_attempt_serial, Some(3))
  original_captured_inputs_release(ledger, originals)
  original_captured_inputs_release(foreign, foreign_originals)
}

///|
test "plural capture permits live backing but keyed child and serialization require settled originals" {
  let (ledger, identity, originals) = original_captured_inputs_fixture(
    settled=false,
  )
  assert_true(original_captured_inputs_prefix_available(ledger, originals))
  let prefix = reserve_attempt(ledger, 0L, 2L, 2L).unwrap()
  assert_true(
    original_captured_inputs_prefix_reservation_available(
      ledger, originals, prefix,
    ),
  )
  mark_cleanup_pending(ledger, originals[1].0).unwrap()
  assert_false(
    original_captured_inputs_prefix_reservation_available(
      ledger, originals, prefix,
    ),
  )
  let assembly = reserve_attempt(ledger, 0L, 3L, 3L).unwrap()
  assert_false(
    original_keyed_inputs_child_preparation_available(
      identity,
      ledger,
      originals,
      assembly,
      0,
      prefix=Some(prefix),
    ),
  )
  settle_reservation(ledger, originals[1].0).unwrap()
  // Still-open first original independently prevents use after pending ACK.
  assert_false(
    original_keyed_inputs_child_preparation_available(
      identity,
      ledger,
      originals,
      assembly,
      0,
      prefix=Some(prefix),
    ),
  )
  let output = retain_allocation(ledger, assembly, 1L).unwrap()
  settle_reservation(ledger, assembly).unwrap()
  assert_false(
    original_keyed_inputs_serialization_preparation_available(
      identity, ledger, originals, prefix, assembly, 0,
    ),
  )
  mark_cleanup_pending(ledger, originals[0].0).unwrap()
  assert_false(
    original_keyed_inputs_serialization_preparation_available(
      identity, ledger, originals, prefix, assembly, 0,
    ),
  )
  settle_reservation(ledger, originals[0].0).unwrap()
  assert_true(
    original_keyed_inputs_serialization_preparation_available(
      identity, ledger, originals, prefix, assembly, 0,
    ),
  )
  release_allocation(ledger, output).unwrap()
  assert_true(
    original_keyed_inputs_prefix_dependents_retired(ledger, originals, prefix),
  )
  settle_reservation(ledger, prefix).unwrap()
  original_captured_inputs_release(ledger, originals)
}

///|
test "plural keyed census preserves child positions spent history and exact cleanup custody" {
  let (ledger, identity, originals) = original_captured_inputs_fixture()
  let (foreign, foreign_identity, foreign_originals) = original_captured_inputs_fixture()
  let prefix = reserve_attempt(ledger, 0L, 2L, 2L).unwrap()
  let assembly = reserve_attempt(ledger, 0L, 3L, 3L).unwrap()
  assert_true(
    original_keyed_inputs_child_preparation_available(
      identity,
      ledger,
      originals,
      assembly,
      0,
      prefix=Some(prefix),
    ),
  )
  assert_false(
    original_keyed_inputs_child_preparation_available(
      foreign_identity,
      ledger,
      originals,
      assembly,
      0,
      prefix=Some(prefix),
    ),
  )
  assert_false(
    original_keyed_inputs_child_preparation_available(
      identity,
      foreign,
      originals,
      assembly,
      0,
      prefix=Some(prefix),
    ),
  )
  assert_false(
    original_keyed_inputs_child_preparation_available(
      identity, ledger, originals, assembly, 0,
    ),
  )
  assert_false(
    original_keyed_inputs_child_preparation_available(
      identity,
      ledger,
      originals,
      prefix,
      0,
      prefix=Some(assembly),
    ),
  )
  let before = ledger_usage(ledger)
  assert_true(reserve_attempt(ledger, 0L, 100L, 0L) is Err(RetentionLimit))
  assert_eq(ledger_usage(ledger), before)
  assert_true(
    original_keyed_inputs_child_preparation_available(
      identity,
      ledger,
      originals,
      assembly,
      0,
      prefix=Some(prefix),
    ),
  )
  let child = reserve_attempt(ledger, 0L, 2L, 2L).unwrap()
  mark_cleanup_pending(ledger, child).unwrap()
  assert_false(
    original_keyed_inputs_child_preparation_available(
      identity,
      ledger,
      originals,
      assembly,
      1,
      prefix=Some(prefix),
    ),
  )
  let child_holding = retain_allocation(ledger, child, 1L).unwrap()
  settle_reservation(ledger, child).unwrap()
  assert_true(
    original_keyed_inputs_child_preparation_available(
      identity,
      ledger,
      originals,
      assembly,
      1,
      prefix=Some(prefix),
    ),
  )
  for count in [-1, 0, 2, 2147483647] {
    assert_false(
      original_keyed_inputs_child_preparation_available(
        identity,
        ledger,
        originals,
        assembly,
        count,
        prefix=Some(prefix),
      ),
    )
  }
  for
    invalid in [
      [],
      [originals[0]],
      [originals[1], originals[0]],
      [originals[0], originals[0]],
      foreign_originals,
    ] {
    assert_false(
      original_keyed_inputs_child_preparation_available(
        identity,
        ledger,
        invalid,
        assembly,
        1,
        prefix=Some(prefix),
      ),
    )
    assert_false(
      original_keyed_inputs_lookup_dependents_retired(
        ledger,
        invalid,
        assembly,
        prefix=Some(prefix),
      ),
    )
    assert_false(
      original_keyed_inputs_prefix_dependents_retired(ledger, invalid, prefix),
    )
  }
  assert_false(
    original_keyed_inputs_serialization_preparation_available(
      identity, ledger, originals, prefix, assembly, 1,
    ),
  )
  let output = retain_allocation(ledger, assembly, 1L).unwrap()
  assert_false(
    original_keyed_inputs_serialization_preparation_available(
      identity, ledger, originals, prefix, assembly, 1,
    ),
  )
  settle_reservation(ledger, assembly).unwrap()
  assert_true(
    original_keyed_inputs_serialization_preparation_available(
      identity, ledger, originals, prefix, assembly, 1,
    ),
  )
  for
    invalid in [
      [],
      [originals[0]],
      [originals[1], originals[0]],
      [originals[0], originals[0]],
      foreign_originals,
    ] {
    assert_false(
      original_keyed_inputs_serialization_preparation_available(
        identity, ledger, invalid, prefix, assembly, 1,
      ),
    )
  }
  assert_false(
    original_keyed_inputs_serialization_preparation_available(
      identity, ledger, originals, assembly, prefix, 1,
    ),
  )
  for count in [-1, 0, 2, 2147483647] {
    assert_false(
      original_keyed_inputs_serialization_preparation_available(
        identity, ledger, originals, prefix, assembly, count,
      ),
    )
  }
  let suffix = reserve_attempt(ledger, 0L, 2L, 2L).unwrap()
  mark_cleanup_pending(ledger, suffix).unwrap()
  assert_false(
    original_keyed_inputs_lookup_dependents_retired(
      ledger,
      originals,
      assembly,
      prefix=Some(prefix),
    ),
  )
  assert_false(
    original_keyed_inputs_prefix_dependents_retired(ledger, originals, prefix),
  )
  settle_reservation(ledger, suffix).unwrap()
  assert_true(
    original_keyed_inputs_lookup_dependents_retired(
      ledger,
      originals,
      assembly,
      prefix=Some(prefix),
    ),
  )
  // Slot counts recover after suffix ACK; absolute attempt history does not.
  assert_false(
    original_keyed_inputs_serialization_preparation_available(
      identity, ledger, originals, prefix, assembly, 1,
    ),
  )
  assert_false(
    original_keyed_inputs_prefix_dependents_retired(ledger, originals, prefix),
  )
  release_allocation(ledger, child_holding).unwrap()
  release_allocation(ledger, output).unwrap()
  assert_true(
    original_keyed_inputs_prefix_dependents_retired(ledger, originals, prefix),
  )
  mark_cleanup_pending(ledger, prefix).unwrap()
  assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
  assert_true(
    original_keyed_inputs_prefix_dependents_retired(ledger, originals, prefix),
  )
  assert_true(reservation_pending(prefix))
  settle_reservation(ledger, prefix).unwrap()
  original_captured_inputs_release(ledger, originals)
  original_captured_inputs_release(foreign, foreign_originals)
}

///|
test "plural unprefixed keyed census rejects lost capture or child holding and spent attempts" {
  let (ledger, identity, originals) = original_captured_inputs_fixture()
  let assembly = reserve_attempt(ledger, 0L, 3L, 3L).unwrap()
  assert_true(
    original_keyed_inputs_child_preparation_available(
      identity, ledger, originals, assembly, 0,
    ),
  )
  assert_true(
    original_keyed_inputs_lookup_dependents_retired(ledger, originals, assembly),
  )
  let child = reserve_attempt(ledger, 0L, 1L, 1L).unwrap()
  let child_holding = retain_allocation(ledger, child, 1L).unwrap()
  settle_reservation(ledger, child).unwrap()
  assert_true(
    original_keyed_inputs_child_preparation_available(
      identity, ledger, originals, assembly, 1,
    ),
  )
  release_allocation(ledger, child_holding).unwrap()
  assert_false(
    original_keyed_inputs_child_preparation_available(
      identity, ledger, originals, assembly, 1,
    ),
  )
  assert_false(
    original_keyed_inputs_child_preparation_available(
      identity, ledger, originals, assembly, 0,
    ),
  )
  release_allocation(ledger, originals[1].1).unwrap()
  assert_false(
    original_keyed_inputs_lookup_dependents_retired(ledger, originals, assembly),
  )
  assert_false(
    original_keyed_inputs_child_preparation_available(
      identity, ledger, originals, assembly, 0,
    ),
  )
  settle_reservation(ledger, assembly).unwrap()
  release_allocation(ledger, originals[0].1).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}
