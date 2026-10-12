///|
// Synthetic allowances prove binding/phase/custody only, not physical bytes,
// installed Model/Entry park, durable ACK or confirmed COMMIT invalidation.
fn client_resource_park_test_scope(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> (ClientModelReadScope, ClientModelReadPreparation, ClientModelReadConsumer) {
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
  let consumer = claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  (scope, read, consumer)
}

///|
test "checked Resource park rejects foreign Run scope consumer and unentered phase" {
  let (compiled, definition, plan) = client_model_read_test_run("resource-park")
  let (other, other_definition, other_plan) = client_model_read_test_run(
    "resource-park-foreign",
  )
  let (scope, _, consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  let (same_run_foreign_scope, _, other_consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  let before = @resources.ledger_usage(scope.ledger)
  for
    (owner, run, graph) in [
      (other, definition, plan),
      (compiled, other_definition, plan),
      (compiled, definition, other_plan),
    ] {
    assert_true(
      park_client_model_read_consumer(scope, consumer, owner, run, graph)
      is Err(ForeignRun),
    )
  }
  assert_true(
    park_client_model_read_consumer(scope, consumer, compiled, definition, plan)
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  enter_client_model_read_consumer(
    other_consumer, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  assert_true(
    park_client_model_read_consumer(
      same_run_foreign_scope, consumer, compiled, definition, plan,
    )
    is Err(Resource(@resources.ForeignOrigin)),
  )
  assert_true(
    park_client_model_read_consumer(
      scope, other_consumer, compiled, definition, plan,
    )
    is Err(Resource(@resources.ForeignOrigin)),
  )
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  assert_true(@resources.original_ledger_inventory_available(scope.identity))
  settle_client_model_read_consumer(consumer, true).unwrap()
  settle_client_model_read_consumer(other_consumer, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_true(
    finish_client_model_read_scope(
      same_run_foreign_scope, compiled, definition, plan, true,
    ).unwrap(),
  )
}

///|
test "checked Resource park keeps exact original token and refuses stop cleanup or early retirement" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "resource-park-live",
  )
  let (scope, read, consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  let (other_scope, _, other_consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  let before = @resources.ledger_usage(scope.ledger)
  let quantities = @resources.quantity_usage(scope.ledger)
  let token = park_client_model_read_consumer(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  for _ in 0..<3 {
    assert_true(
      client_model_resource_park_current(
        token, scope, compiled, definition, plan,
      )
      is Some(same) &&
      physical_equal(same, token),
    )
    assert_true(
      client_model_resource_park_current(
        token, other_scope, compiled, definition, plan,
      )
      is None,
    )
  }
  assert_true(
    park_client_model_read_consumer(scope, consumer, compiled, definition, plan)
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  assert_eq(
    stop_client_model_read_consumer(consumer),
    Err(Resource(@resources.Resource(@resources.ResourceParked))),
  )
  assert_eq(
    stop_client_model_read_checked(scope, read, compiled, definition, plan),
    Err(Resource(@resources.Resource(@resources.ResourceParked))),
  )
  for complete in [false, true] {
    assert_eq(
      settle_client_model_read_consumer(consumer, complete),
      Err(Resource(@resources.Resource(@resources.ResourceParked))),
    )
    assert_eq(
      finish_client_model_read_scope(
        scope, compiled, definition, plan, complete,
      ),
      Err(Resource(@resources.Resource(@resources.ResourceParked))),
    )
  }
  assert_eq(
    retire_client_model_resource_park(token),
    Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  assert_eq(@resources.quantity_usage(scope.ledger), quantities)
  // No actual journal receipt was supplied. This original Owner remains
  // parked/pending: do not simulate product unpark or declare it released.
  assert_true(
    client_model_resource_park_current(token, scope, compiled, definition, plan)
    is Some(_),
  )
  settle_client_model_read_consumer(other_consumer, true).unwrap()
  assert_true(
    finish_client_model_read_scope(
      other_scope, compiled, definition, plan, true,
    ).unwrap(),
  )
}

///|
test "checked Resource park binds current handoff rather than an admitted historical aggregate" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "resource-park-handoff",
  )
  let (scope, _, consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  let (ledger, capacity) = @resources.handoff_funded_read_consumer_capacity(
    consumer.consumer,
    scope.origin,
    1L,
    1L,
  ).unwrap()
  assert_true(physical_equal(ledger, scope.ledger))
  assert_true(@resources.funded_read_consumer_origin(consumer.consumer) is None)
  let before = @resources.ledger_usage(ledger)
  let token = park_client_model_read_consumer(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  assert_true(
    client_model_resource_park_current(token, scope, compiled, definition, plan)
    is Some(same) &&
    physical_equal(same, token),
  )
  assert_eq(
    @resources.settle_capacity(ledger, capacity),
    Err(@resources.ResourceParked),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(
    retire_client_model_resource_park(token),
    Err(Resource(@resources.CleanupPending)),
  )
}
