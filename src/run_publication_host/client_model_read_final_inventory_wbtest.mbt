///|
test "checked original model read final inventory binds original Run without Ledger getter" {
  let (compiled, definition, plan) = client_model_read_test_run("read-final")
  let (_, foreign_definition, _) = client_model_read_test_run(
    "foreign-read-final",
  )
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
    compiled, definition, plan, ledger, bootstrap, 1, 0, 0,
  ).unwrap()
  let read = prepare_client_model_read(scope, 7L, 5L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    finish_client_model_read_inventory(
      read, compiled, foreign_definition, plan, true,
    )
    is Err(ForeignRun),
  )
  assert_true(
    finish_client_model_read_inventory(read, compiled, definition, plan, true)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(client_model_read_available(read, compiled, definition, plan))
  stop_client_model_read(read).unwrap()
  assert_true(
    settle_client_model_read(read, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  settle_client_model_read(read, true).unwrap()
  assert_false(
    finish_client_model_read_inventory(read, compiled, definition, plan, false).unwrap(),
  )
  assert_true(@resources.capacity_reservation_open(bootstrap))
  assert_true(
    finish_client_model_read_inventory(read, compiled, definition, plan, true).unwrap(),
  )
  assert_false(@resources.capacity_reservation_open(bootstrap))
  assert_true(
    finish_client_model_read_inventory(read, compiled, definition, plan, true)
    is Err(Resource(@resources.SpentClaim)),
  )
}
