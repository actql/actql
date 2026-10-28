///|
// This uses the original checked fixture and synthetic byte allowances. It
// executes real Core callers, not installed physical funding or Store/CAS.
fn model_resource_park_test_start(
  max_reservations? : Int = 4,
) -> (
  Execution,
  @publication_host.ClientModelReadScope,
  @publication_host.ClientModelReadConsumer,
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
  @publication_host.ClientInferPlanGraph,
  @resources.Ledger,
) {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let ledger = @resources.create_ledger({
    ..limits.model.ledger,
    attempts: Int::min(limits.model.ledger.attempts, 4),
    transfer_bytes: Int64::min(limits.model.ledger.transfer_bytes, 133072L),
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, max_reservations, 2, 0,
  ).unwrap()
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  let consumer = @publication_host.claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  let active = start_original_model_preparation(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    original_funded_start_provider(Ref(0)),
    limits,
    compiled,
    definition,
    plan,
    consumer,
    7L,
    5L,
    100L,
    5L,
  ).unwrap()
  (active, scope, consumer, compiled, definition, plan, ledger)
}

///|
test "original parked Resource caller refuses cancellation before changing execution" {
  let (active, scope, consumer, compiled, definition, plan, ledger) = model_resource_park_test_start()
  let prepared = active.original_preparation.unwrap()
  let input = active.input
  let work = active.work
  let before = @resources.ledger_usage(ledger)
  let park = @publication_host.park_client_model_read_consumer(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  assert_false(cancel(active))
  assert_false(active.cancelled || active.reclaimed)
  assert_true(active.phase is Input)
  assert_true(physical_equal(active.input, input))
  assert_true(physical_equal(active.original_preparation.unwrap(), prepared))
  assert_eq(active.work, work)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    @publication_host.client_model_resource_park_current(
      park, scope, compiled, definition, plan,
    )
    is Some(same) &&
    physical_equal(same, park),
  )
  // Pending is intentional. No COMMIT receipt exists, so this cannot resume,
  // reclaim the read, or assert physical cancellation/cleanup completion.
  assert_eq(
    @publication_host.retire_client_model_resource_park(park),
    Err(@publication_host.Resource(@resources.CleanupPending)),
  )
}

///|
test "original parked Resource caller retains completed Model and input borrows on cleanup refusal" {
  let (active, scope, consumer, compiled, definition, plan, ledger) = model_resource_park_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let preparation = active.original_preparation.unwrap()
  let model = active.model.unwrap()
  let rows = active.rows.unwrap()
  let call_scope = active.call_scope.unwrap()
  let output = active.completed.unwrap()
  let before = @resources.ledger_usage(ledger)
  let quantities = @resources.quantity_usage(ledger)
  let park = @publication_host.park_client_model_read_consumer(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  for _ in 0..<2 {
    assert_true(
      cleanup(active)
      is Err(
        OriginalCapacity(
          @publication_host.Read(
            @publication_host.Resource(
              @resources.Resource(@resources.ResourceParked)
            )
          )
        )
      ),
    )
    assert_false(active.reclaimed)
    assert_true(
      physical_equal(active.original_preparation.unwrap(), preparation),
    )
    assert_true(physical_equal(active.model.unwrap(), model))
    assert_true(physical_equal(active.rows.unwrap(), rows))
    assert_true(physical_equal(active.call_scope.unwrap(), call_scope))
    assert_true(physical_equal(active.completed.unwrap(), output))
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_eq(@resources.quantity_usage(ledger), quantities)
    assert_true(
      @publication_host.client_model_resource_park_current(
        park, scope, compiled, definition, plan,
      )
      is Some(same) &&
      physical_equal(same, park),
    )
  }
}
