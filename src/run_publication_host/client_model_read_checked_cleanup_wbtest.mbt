///|
test "checked read cleanup keeps original custody after stopping and refuses foreign Runs" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "cleanup-original",
  )
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "cleanup-foreign",
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
  let consumer = claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  stop_client_model_read_consumer(consumer)
  assert_false(client_model_read_available(read, compiled, definition, plan))
  let before = @resources.ledger_usage(ledger)
  for
    (owner, run, graph) in [
      (foreign, definition, plan),
      (compiled, foreign_definition, plan),
      (compiled, definition, foreign_plan),
    ] {
    for complete in [false, true] {
      assert_true(
        settle_client_model_read_checked(read, owner, run, graph, complete)
        is Err(ForeignRun),
      )
      assert_eq(@resources.ledger_usage(ledger), before)
    }
  }
  assert_true(
    settle_client_model_read_checked(read, compiled, definition, plan, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  settle_client_model_read_checked(read, compiled, definition, plan, true).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 3L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 2L)
  assert_true(@resources.funded_read_consumer_origin(consumer.consumer) is None)
  assert_false(
    finish_client_model_read_scope(scope, compiled, definition, plan, false).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 3L)
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_true(
    settle_client_model_read_checked(read, compiled, definition, plan, true)
    is Err(Resource(@resources.SpentClaim)),
  )
}

///|
test "checked read cleanup does not claim the never-started read or acknowledge whole Run" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "cleanup-unstarted",
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
    settle_client_model_read_checked(read, compiled, definition, plan, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    claim_client_model_read_preparation(
      read, compiled, definition, plan, 7L, 5L,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  settle_client_model_read_checked(read, compiled, definition, plan, true).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_false(
    finish_client_model_read_scope(scope, compiled, definition, plan, false).unwrap(),
  )
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}
