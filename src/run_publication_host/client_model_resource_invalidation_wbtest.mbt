///|
// Resource/Scope intent and inner transition only. These do not authenticate
// journal COMMIT and intentionally do not require dispatch/approval/Allow.
test "checked invalidation intent preserves original Scope Run binding" {
  let (compiled, definition, plan) = client_model_read_test_run("invalidation")
  let (scope, _, consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  let (other, _, other_consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  let park = park_client_model_read_consumer(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  let request = begin_client_model_resource_invalidation(
    park, scope, compiled, definition, plan,
  ).unwrap()
  let before = @resources.ledger_usage(scope.ledger)
  assert_true(
    client_model_resource_invalidation_current(
      request, park, scope, compiled, definition, plan,
    )
    is Some(same) &&
    physical_equal(same, request),
  )
  assert_true(
    client_model_resource_invalidation_current(
      request, park, other, compiled, definition, plan,
    )
    is None,
  )
  assert_true(
    consume_client_model_resource_invalidation(
      request, park, other, compiled, definition, plan,
    )
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  consume_client_model_resource_invalidation(
    request, park, scope, compiled, definition, plan,
  ).unwrap()
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  assert_true(
    consume_client_model_resource_invalidation(
      request, park, scope, compiled, definition, plan,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  assert_true(
    client_model_resource_park_current(park, scope, compiled, definition, plan)
    is None,
  )
  assert_true(
    client_model_resource_invalidation_current(
      request, park, scope, compiled, definition, plan,
    )
    is None,
  )
  settle_client_model_read_consumer(consumer, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  settle_client_model_read_consumer(other_consumer, true).unwrap()
  assert_true(
    finish_client_model_read_scope(other, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "checked invalidation foreign Run refuses while original request remains pending" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "invalidation-run",
  )
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "invalidation-foreign",
  )
  let (scope, _, consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  let park = park_client_model_read_consumer(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  let request = begin_client_model_resource_invalidation(
    park, scope, compiled, definition, plan,
  ).unwrap()
  let before = @resources.ledger_usage(scope.ledger)
  for
    (owner, run, graph) in [
      (foreign, definition, plan),
      (compiled, foreign_definition, plan),
      (compiled, definition, foreign_plan),
    ] {
    assert_true(
      consume_client_model_resource_invalidation(
        request, park, scope, owner, run, graph,
      )
      is Err(ForeignRun),
    )
  }
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  assert_true(
    client_model_resource_invalidation_current(
      request, park, scope, compiled, definition, plan,
    )
    is Some(_),
  )
  assert_true(
    settle_client_model_read_consumer(consumer, false)
    is Err(Resource(@resources.Resource(@resources.ResourceParked))),
  )
  // No external confirmed COMMIT supplied: original request remains pending.
}
