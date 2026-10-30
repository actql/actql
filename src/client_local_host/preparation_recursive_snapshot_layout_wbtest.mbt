///|
test "recursive snapshot geometry covers independent nested Unicode canonical storage" {
  // Bare rows:32 UTF-8 bytes,7 value nodes,5 open containers. The logical
  // relation wrapper adds28 bytes,2 value nodes and one container.
  let wire = "[{\"x\":{\"a\":[1,{\"b\":\"東京\"}]}}]"
  let quote = recursive_snapshot_layout(60, 9, 6, 1, 1).unwrap()
  let source = @source.parse_json(wire, {
    max_input_bytes: 32,
    max_nodes: 7,
    max_depth: 5,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 7,
    max_depth: 5,
    max_string_bytes: 32,
    max_total_string_bytes: 32,
  }).unwrap()
  let admission = @identity.start_cursor_admission(
    cursor,
    7,
    5,
    32,
    32,
    data_keys=true,
  ).unwrap()
  let mut value : @identity.CanonicalValue? = None
  for _ in 0..<1000 {
    match @identity.advance_cursor_admission(admission) {
      @identity.CursorAdmissionContinue => ()
      @identity.CursorAdmissionComplete(v, _, _) => {
        value = Some(v)
        break
      }
      _ => fail("independent nested cursor admission")
    }
  }
  let actual = @identity.representation_extent(value.unwrap(), 7, 5, 32).unwrap()
  assert_eq((actual.nodes, actual.arrays, actual.objects), (7L, 2L, 3L))
  let containers = actual.arrays + actual.objects
  let measured : @execution.PreparationRepresentationUnits = {
    record_headers: actual.nodes + 3L * containers + 3L + 4L,
    reference_slots: actual.nodes +
    2L * containers +
    actual.array_backing_slots +
    actual.object_backing_slots +
    6L,
    scalar_words: actual.nodes + 2L * containers,
    owned_utf16_units: 5L,
    owned_wire_bytes: 0L,
  }
  assert_true(
    @execution.preparation_representation_cost(quote.retained).unwrap() >=
    @execution.preparation_representation_cost(measured).unwrap(),
  )
  let writer = @encode.writer(32, 7, 5)
  @identity.emit_value(value.unwrap(), writer)
  assert_eq(@encode.finish(writer), wire)
  assert_true(recursive_snapshot_layout(30, 3, 2, 0, 0) is Some(_))
  assert_true(recursive_snapshot_layout(60, 9, 9, 1, 1) is None)
  assert_true(recursive_snapshot_layout(60, 2, 6, 1, 1) is None)
  assert_true(recursive_snapshot_layout(60, 9, 6, -1, 1) is None)
  assert_true(recursive_snapshot_layout(60, 2147483647, 6, 1, 1) is None)
}

///|
test "recursive snapshot one byte short refuses before constructor and exact fit keeps original cleanup" {
  let (value, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      ()
    },
  )
  let layout = recursive_snapshot_layout(60, 9, 6, 1, 1).unwrap()
  let retained = @execution.preparation_representation_cost(layout.retained).unwrap() +
    96L
  let temporary = @execution.preparation_representation_cost(layout.temporary).unwrap()
  let before = @resources.ledger_usage(ledger)
  let other = @resources.reserve_capacity(
    ledger,
    536870912L - before.reserved_retention_bytes - retained + 1L,
    0L,
  ).unwrap()
  assert_true(
    reserve_publication_constructor(value, retained, temporary)
    is Err(
      Capacity(
        @resources.PreparationCapacityIssue::Resource(
          @resources.LedgerIssue::RetentionLimit
        )
      )
    ),
  )
  assert_eq(value.retained_quote, 1000000L)
  assert_true(value.snapshot is None)
  assert_true(value.completed_snapshots.is_empty())
  @resources.settle_capacity(ledger, other).unwrap()
  let exact = @resources.reserve_capacity(
    ledger,
    536870912L - before.reserved_retention_bytes - retained,
    0L,
  ).unwrap()
  reserve_publication_constructor(value, retained, temporary).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    536870912L,
  )
  assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
  clear_program_publication(value)
  assert_true(@resources.return_preparation_body_borrow(value.holder).unwrap())
  @resources.settle_capacity(ledger, exact).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}
