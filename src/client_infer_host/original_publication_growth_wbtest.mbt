///|
// Actual checked Model/Scope and original byte reservation, with explicit
// fixture provider/allowances. This is not installed physical backing or E2E.
test "original publication grows one live token from small demand without new work" {
  let (active, ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let before = @resources.ledger_usage(ledger)
  let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
  let initial = @resources.ledger_usage(ledger)
  assert_eq(
    initial.reserved_retention_bytes,
    before.reserved_retention_bytes + 1L,
  )
  grow_original_infer_publication_capacity(active, capacity, 300L, 9L).unwrap()
  let grown = @resources.ledger_usage(ledger)
  assert_eq(
    grown.reserved_retention_bytes,
    before.reserved_retention_bytes + 300L,
  )
  assert_eq(
    grown.reserved_execution_bytes,
    before.reserved_execution_bytes + 9L,
  )
  assert_eq(grown.live_reservations, initial.live_reservations)
  assert_eq(grown.attempts, initial.attempts)
  assert_eq(grown.transferred_bytes, initial.transferred_bytes)
  assert_true(
    @model.original_model_publication_capacity_covers(capacity, 300L, 9L),
  )
  // A smaller next demand keeps the previous peak, not a refund or reissue.
  grow_original_infer_publication_capacity(active, capacity, 2L, 0L).unwrap()
  assert_eq(@resources.ledger_usage(ledger), grown)
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "original publication headroom refusal keeps same token available for bounded demand" {
  let (active, ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let limits = @resources.ledger_limits(ledger)
  assert_true(
    grow_original_infer_publication_capacity(
      active,
      capacity,
      limits.retained_bytes,
      1L,
    )
    is Err(Model(@model.Ledger(@resources.RetentionLimit))),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    @model.original_model_publication_capacity_covers(capacity, 1L, 1L),
  )
  grow_original_infer_publication_capacity(active, capacity, 30L, 4L).unwrap()
  assert_eq(@resources.ledger_limits(ledger), limits)
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "original publication refuses foreign stopped and retired originals without growth" {
  let (active, ledger, consumer) = original_observation_test_start()
  let (foreign, foreign_ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_true(fixture_finish(foreign) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let foreign_before = @resources.ledger_usage(foreign_ledger)
  assert_true(
    grow_original_infer_publication_capacity(foreign, capacity, 30L, 4L)
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(foreign_ledger), foreign_before)
  @publication_host.stop_client_model_read_consumer(consumer).unwrap()
  assert_true(
    grow_original_infer_publication_capacity(active, capacity, 30L, 4L)
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  let retired = @resources.ledger_usage(ledger)
  assert_true(
    grow_original_infer_publication_capacity(active, capacity, 30L, 4L)
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(ledger), retired)
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(foreign).unwrap())
}
