///|
test "checked parked read capacity binds the actual Scope Run and both original envelopes" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "parked-capacity",
  )
  let (other, other_definition, other_plan) = client_model_read_test_run(
    "parked-capacity-foreign",
  )
  let (scope, read, consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  let (foreign_scope, _, foreign_consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  let park = park_client_model_read_consumer(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  let before = @resources.ledger_usage(scope.ledger)
  let quantities = @resources.quantity_usage(scope.ledger)
  for _ in 0..<3 {
    assert_true(
      client_model_parked_read_capacity_available(
        park, scope, compiled, definition, plan, 7L, 5L,
      ),
    )
    assert_false(
      client_model_parked_read_capacity_available(
        park, scope, compiled, definition, plan, 8L, 5L,
      ),
    )
    assert_false(
      client_model_parked_read_capacity_available(
        park, scope, compiled, definition, plan, 7L, 6L,
      ),
    )
    assert_false(
      client_model_parked_read_capacity_available(
        park, foreign_scope, compiled, definition, plan, 7L, 5L,
      ),
    )
    assert_false(
      client_model_parked_read_capacity_available(
        park, scope, other, definition, plan, 7L, 5L,
      ),
    )
    assert_false(
      client_model_parked_read_capacity_available(
        park, scope, compiled, other_definition, plan, 7L, 5L,
      ),
    )
    assert_false(
      client_model_parked_read_capacity_available(
        park, scope, compiled, definition, other_plan, 7L, 5L,
      ),
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
  }
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  assert_eq(@resources.quantity_usage(scope.ledger), quantities)
  assert_true(
    client_model_resource_park_current(park, scope, compiled, definition, plan)
    is Some(_),
  )
  settle_client_model_read_consumer(foreign_consumer, true).unwrap()
  assert_true(
    finish_client_model_read_scope(
      foreign_scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  // No actual journal receipt was supplied. Retain the original parked token;
  // do not synthesize unpark or physical cleanup from this predicate.
}
