///|
test "checked handed-off covers rejects foreign Run and same-Run foreign Scope" {
  let (compiled, definition, plan) = client_model_read_test_run("handed-covers")
  let (scope, _, consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  let (foreign_scope, _, _) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  assert_false(
    client_model_handed_off_read_capacity_available(
      scope, consumer, compiled, definition, plan, 7L, 5L,
    ),
  )
  @resources.handoff_funded_read_consumer_capacity(
    consumer.consumer,
    scope.origin,
    1L,
    1L,
  ).unwrap()
  |> ignore
  let before = @resources.ledger_usage(scope.ledger)
  assert_true(
    client_model_handed_off_read_capacity_available(
      scope, consumer, compiled, definition, plan, 7L, 5L,
    ),
  )
  assert_false(
    client_model_handed_off_read_capacity_available(
      foreign_scope, consumer, compiled, definition, plan, 7L, 5L,
    ),
  )
  let (_, foreign_definition, _) = client_model_read_test_run("handed-foreign")
  assert_false(
    client_model_handed_off_read_capacity_available(
      scope, consumer, compiled, foreign_definition, plan, 7L, 5L,
    ),
  )
  assert_false(
    client_model_handed_off_read_capacity_available(
      scope, consumer, compiled, definition, plan, 8L, 5L,
    ),
  )
  assert_eq(@resources.ledger_usage(scope.ledger), before)
}
