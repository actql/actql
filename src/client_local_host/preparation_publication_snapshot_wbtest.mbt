///|
/// Per original Result: wrapper(2 refs), issuer Some and publication-slot Some.
/// Distinct from the final canonical snapshot, whose layout owns row payloads.
let publication_snapshot_wrapper_units : @execution.PreparationRepresentationUnits = {
  record_headers: 3L,
  reference_slots: 4L,
  scalar_words: 2L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
let publication_snapshot_wrapper_retained : Int64 = @execution.preparation_representation_cost(
  publication_snapshot_wrapper_units,
).unwrap()

///|
test "typed snapshot wrapper retains one shared-tariff control packet" {
  assert_eq(publication_snapshot_wrapper_retained, 96L)
  assert_eq(
    @execution.preparation_representation_cost(
      publication_snapshot_wrapper_units,
    ),
    Some(96L),
  )
}

///|
/// No synthetic raw issuer is fabricated: these are terminal/foreign handles
/// under a real preparation holder. Positive producer lineage is exercised by
/// the ordinary public publication suite, not claimed by this custody test.
test "typed snapshot foreign terminal handle cannot cut the original slot" {
  let (publication, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      ()
    },
  )
  let original : ClientProgramSnapshot = { publication, issuer: None, }
  let foreign : ClientProgramSnapshot = { publication, issuer: None, }
  publication.snapshot = Some(original)
  assert_true(program_snapshot_slot_matches(original))
  assert_false(program_snapshot_slot_matches(foreign))
  assert_false(program_snapshot_current(original))
  assert_true(advance_program_snapshot(foreign, 1) is Err(ForeignOriginal))
  assert_true(finish_program_snapshot(foreign) is Err(ForeignOriginal))
  cancel_program_snapshot(foreign)
  assert_true(program_snapshot_slot_matches(original))
  cancel_program_snapshot(original)
  assert_true(publication.snapshot is None)
  cancel_program_snapshot(original)
  assert_eq(publication.next_snapshot_index, 0)
  assert_eq(publication.completed_snapshots.length(), 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 1000000L)
  assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
  clear_program_publication(publication)
  assert_true(
    @resources.preparation_body_retirement_started(publication.holder),
  )
  assert_true(
    @resources.return_preparation_body_borrow(publication.holder).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}
