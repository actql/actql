///|
// Synthetic allowances validate the real checked binding/lifetime, not a
// numerical physical profile, installed Model park or actual Store/journal.
fn client_current_write_test_scope(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  planning : Int,
) -> (ClientModelReadScope, ClientModelReadConsumer) {
  let ledger = @resources.create_ledger({
    planning_work: planning,
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
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  (scope, consumer)
}

///|
test "checked current Writer uses exact Scope park and cursor with independent work" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "current-writer",
  )
  let (scope, consumer) = client_current_write_test_scope(
    compiled, definition, plan, 17,
  )
  let park = park_client_model_read_consumer_for_state_write(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  let writer = @encode.writer(1000, 200, 10)
  let value = start_client_model_current_state_write(
    park, scope, compiled, definition, plan, writer,
  ).unwrap()
  let before = @resources.ledger_usage(scope.ledger)
  let mut work = 0
  for _ in 0..<17 {
    let poll = advance_client_model_current_state_write(
      value, park, scope, compiled, definition, plan, 1,
    )
    match poll {
      @resources.StateWriteContinue(work=n) => work += n
      @resources.StateWriteComplete(work=n) => work += n
      _ => abort("current Writer unexpectedly refused")
    }
  }
  assert_eq(work, 17)
  assert_eq(@resources.ledger_usage(scope.ledger).planning_work, 17)
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  assert_true(@encode.finish(writer).contains("\"parked\""))
  assert_true(
    @resources.original_current_state_write_current(value, park) is None,
  )
  assert_true(
    client_model_resource_park_current(park, scope, compiled, definition, plan)
    is Some(_),
  )
  assert_true(
    settle_client_model_read_consumer(consumer, false)
    is Err(Resource(@resources.Resource(@resources.ResourceParked))),
  )
  // No real COMMIT receipt exists. Keep the original park/custody pending.
}

///|
test "checked current Writer refuses foreign scopes parks and cursors before progress" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "current-writer-foreign",
  )
  let (scope, consumer) = client_current_write_test_scope(
    compiled, definition, plan, 17,
  )
  let (other, other_consumer) = client_current_write_test_scope(
    compiled, definition, plan, 17,
  )
  let before = @resources.ledger_usage(scope.ledger)
  assert_true(
    park_client_model_read_consumer_for_state_write(
      other, consumer, compiled, definition, plan,
    )
    is Err(Resource(@resources.ForeignOrigin)),
  )
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  let park = park_client_model_read_consumer_for_state_write(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  let other_park = park_client_model_read_consumer_for_state_write(
    other, other_consumer, compiled, definition, plan,
  ).unwrap()
  let writer = @encode.writer(1000, 200, 10)
  let other_writer = @encode.writer(1000, 200, 10)
  assert_true(
    start_client_model_current_state_write(
      park, other, compiled, definition, plan, writer,
    )
    is Err(@resources.Original(@resources.ChangedOriginalState)),
  )
  assert_eq(@encode.writer_progress(writer), (0, 0, 0))
  let value = start_client_model_current_state_write(
    park, scope, compiled, definition, plan, writer,
  ).unwrap()
  let other_value = start_client_model_current_state_write(
    other_park, other, compiled, definition, plan, other_writer,
  ).unwrap()
  assert_true(
    advance_client_model_current_state_write(
      other_value, park, scope, compiled, definition, plan, 1,
    )
    is @resources.StateWriteFailed(
      @resources.Original(@resources.ChangedOriginalState),
      work=0
    ),
  )
  assert_true(
    advance_client_model_current_state_write(
      value, park, other, compiled, definition, plan, 1,
    )
    is @resources.StateWriteFailed(
      @resources.Original(@resources.ChangedOriginalState),
      work=0
    ),
  )
  assert_eq(@encode.writer_progress(writer), (0, 0, 0))
  assert_eq(@encode.writer_progress(other_writer), (0, 0, 0))
  assert_true(
    advance_client_model_current_state_write(
      value, park, scope, compiled, definition, plan, 1,
    )
    is @resources.StateWriteContinue(work=1),
  )
  cancel_client_model_current_state_write(value)
  cancel_client_model_current_state_write(other_value)
  assert_true(
    @resources.original_current_state_write_current(value, park) is None,
  )
  assert_true(
    client_model_resource_park_current(park, scope, compiled, definition, plan)
    is Some(_),
  )
}

///|
test "checked current Writer exact one-short and ordinary park keep original custody" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "current-writer-short",
  )
  let (scope, consumer) = client_current_write_test_scope(
    compiled, definition, plan, 16,
  )
  let before = @resources.ledger_usage(scope.ledger)
  assert_true(
    park_client_model_read_consumer_for_state_write(
      scope, consumer, compiled, definition, plan,
    )
    is Err(Resource(@resources.Resource(@resources.PlanningLimit))),
  )
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  let park = park_client_model_read_consumer(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  let writer = @encode.writer(1000, 200, 10)
  assert_true(
    start_client_model_current_state_write(
      park, scope, compiled, definition, plan, writer,
    )
    is Err(@resources.Original(@resources.SpentClaim)),
  )
  assert_eq(@encode.writer_progress(writer), (0, 0, 0))
  assert_true(
    client_model_resource_park_current(park, scope, compiled, definition, plan)
    is Some(_),
  )
  @encode.cancel_writer(writer)
}
