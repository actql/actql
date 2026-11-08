///|
test "original checked Model Read grows before its one consumer enter and keeps exact Run cleanup" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "source-body-preparation",
  )
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "foreign-source-body",
  )
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 40L,
    execution_bytes: 30L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 2, 0, 0,
  ).unwrap()
  let read = prepare_client_model_read(scope, 7L, 5L).unwrap()
  let consumer = claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    grow_client_model_read_preparing_capacity(
      read, consumer, foreign, foreign_definition, foreign_plan, 10L, 8L,
    )
    is Err(ForeignRun),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  grow_client_model_read_preparing_capacity(
    read, consumer, compiled, definition, plan, 10L, 8L,
  ).unwrap()
  assert_true(
    client_model_read_consumer_available(
      consumer, compiled, definition, plan, 10L, 8L,
    ),
  )
  assert_true(
    grow_client_model_read_preparation_consumer_capacity(
      read, consumer, compiled, definition, plan, 10L, 8L,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  enter_client_model_read_consumer(
    consumer, compiled, definition, plan, 10L, 8L,
  ).unwrap()
  assert_true(
    enter_client_model_read_consumer(
      consumer, compiled, definition, plan, 10L, 8L,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  assert_true(
    grow_client_model_read_preparing_capacity(
      read, consumer, compiled, definition, plan, 11L, 9L,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  grow_client_model_read_preparation_consumer_capacity(
    read, consumer, compiled, definition, plan, 11L, 9L,
  ).unwrap()
  stop_client_model_read_checked(scope, read, compiled, definition, plan).unwrap()
  settle_client_model_read_checked(read, compiled, definition, plan, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.transferred_bytes, before.transferred_bytes)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
}
