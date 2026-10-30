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
