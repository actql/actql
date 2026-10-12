///|
test "checked early model consumer rejects duplicate and foreign before allocation" {
  let (compiled, definition, plan) = client_model_read_test_run("consumer")
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "foreign-consumer",
  )
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 20L,
    execution_bytes: 12L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 2, 0, 0,
  ).unwrap()
  let read = prepare_client_model_read(scope, 7L, 5L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    claim_client_model_read_preparation(
      read, foreign, foreign_definition, foreign_plan, 7L, 5L,
    )
    is Err(ForeignRun),
  )
  assert_true(
    claim_client_model_read_preparation(
      read, compiled, definition, plan, 8L, 5L,
    )
    is Err(Resource(@resources.Resource(@resources.RetentionLimit))),
  )
  assert_true(
    claim_client_model_read_preparation(
      read, compiled, definition, plan, 7L, 6L,
    )
    is Err(Resource(@resources.Resource(@resources.ExecutionLimit))),
  )
  let consumer = claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  assert_true(
    client_model_read_consumer_available(
      consumer, compiled, definition, plan, 7L, 5L,
    ),
  )
  assert_true(
    claim_client_model_read_preparation(
      read, compiled, definition, plan, 7L, 5L,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  assert_false(
    client_model_read_preparation_available(
      read,
      compiled,
      definition,
      plan,
      5L,
      retained_bytes=7L,
    ),
  )
  assert_false(
    client_model_read_consumer_available(
      consumer, compiled, foreign_definition, plan, 7L, 5L,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    enter_client_model_read_consumer(
      consumer, compiled, foreign_definition, plan, 7L, 5L,
    )
    is Err(ForeignRun),
  )
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  assert_true(
    enter_client_model_read_consumer(
      consumer, compiled, definition, plan, 7L, 5L,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  stop_client_model_read_consumer(consumer).unwrap()
  assert_false(
    client_model_read_consumer_available(
      consumer, compiled, definition, plan, 7L, 5L,
    ),
  )
  assert_true(
    settle_client_model_read_consumer(consumer, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  settle_client_model_read_consumer(consumer, true).unwrap()
  assert_false(
    client_model_read_consumer_available(
      consumer, compiled, definition, plan, 7L, 5L,
    ),
  )
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
}
