///|
test "checked original read scope cleanup retains failed issuance custody" {
  let (compiled, definition, plan) = client_model_read_test_run("scope-failed")
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "scope-foreign",
  )
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 9L,
    execution_bytes: 7L,
  }).unwrap()
  let quantities : @resources.QuantityAmounts = {
    tokens: 3L,
    cost_units: 5L,
    duration_ms: 7L,
  }
  @resources.configure_quantities(ledger, quantities).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 1, 0, 0,
  ).unwrap()
  assert_true(client_model_read_scope_live(scope, compiled, definition, plan))
  assert_false(client_model_read_scope_live(scope, foreign, definition, plan))
  assert_false(
    client_model_read_scope_live(scope, compiled, foreign_definition, plan),
  )
  assert_false(
    client_model_read_scope_live(scope, compiled, definition, foreign_plan),
  )
  let before = @resources.ledger_usage(ledger)
  let before_quantities = @resources.quantity_usage(ledger)
  assert_true(
    prepare_client_model_read(scope, 7L, 5L)
    is Err(Resource(@resources.Resource(@resources.RetentionLimit))),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.quantity_usage(ledger), before_quantities)
  assert_true(
    finish_client_model_read_scope(
      scope, foreign, foreign_definition, foreign_plan, true,
    )
    is Err(ForeignRun),
  )
  assert_true(
    finish_client_model_read_scope(
      scope, compiled, foreign_definition, plan, true,
    )
    is Err(ForeignRun),
  )
  assert_true(
    finish_client_model_read_scope(
      scope, compiled, definition, foreign_plan, true,
    )
    is Err(ForeignRun),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(
    finish_client_model_read_scope(scope, compiled, definition, plan, false).unwrap(),
  )
  // Actual Resource closing differs from graceful Host closing. It refuses
  // new work but still preserves the same bootstrap and cleanup responsibility.
  assert_false(client_model_read_scope_live(scope, compiled, definition, plan))
  assert_true(@resources.capacity_reservation_open(bootstrap))
  assert_eq(@resources.ledger_usage(ledger), before)
  // A failed descriptor issue is not reset into a new read or new serial.
  assert_true(
    prepare_client_model_read(scope, 7L, 5L)
    is Err(Resource(@resources.IncompleteInventory)),
  )
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_false(@resources.capacity_reservation_open(bootstrap))
  assert_false(client_model_read_scope_live(scope, compiled, definition, plan))
  assert_eq(@resources.quantity_usage(ledger), before_quantities)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true)
    is Err(Resource(@resources.SpentClaim)),
  )
}

///|
test "checked original read scope cleanup cannot bypass live read or zero byte holding" {
  let (compiled, definition, plan) = client_model_read_test_run("scope-live")
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 10L,
    execution_bytes: 7L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 2, 1, 0,
  ).unwrap()
  let read = prepare_client_model_read(scope, 7L, 5L).unwrap()
  let child = @resources.reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  let holding = @resources.retain_allocation(ledger, child, 0L).unwrap()
  assert_false(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(
    settle_client_model_read(read, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_false(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  settle_client_model_read(read, true).unwrap()
  @resources.settle_reservation(ledger, child).unwrap()
  assert_false(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(@resources.capacity_reservation_open(bootstrap))
  @resources.release_allocation(ledger, holding).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_false(@resources.capacity_reservation_open(bootstrap))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}
