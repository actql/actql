///|
// Real checked original Scope/Model callers with synthetic byte grants. These
// tests prove byte-only admission and borrow lifetime, not a physical profile,
// Store ACK, durable authentication or public Named Result acceptance.
test "original publication capacity uses same Ledger and pins cleanup until release" {
  let (active, _, _, _, _, _, ledger) = model_resource_park_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let model = active.model.unwrap()
  let scope = active.call_scope.unwrap()
  let before = @resources.ledger_usage(ledger)
  let quantities = @resources.quantity_usage(ledger)
  let capacity = @model.reserve_original_model_publication_capacity(
    model, scope, 7L, 5L,
  ).unwrap()
  let funded = @resources.ledger_usage(ledger)
  assert_true(
    @model.original_model_publication_capacity_current(capacity, model, scope),
  )
  assert_eq(
    funded.reserved_retention_bytes,
    before.reserved_retention_bytes + 7L,
  )
  assert_eq(
    funded.reserved_execution_bytes,
    before.reserved_execution_bytes + 5L,
  )
  assert_eq(funded.attempts, before.attempts)
  assert_eq(funded.planning_work, before.planning_work)
  assert_eq(funded.transferred_bytes, before.transferred_bytes)
  assert_eq(funded.reserved_transfer_bytes, before.reserved_transfer_bytes)
  assert_eq(funded.uncertain_transfer_bytes, before.uncertain_transfer_bytes)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  assert_false(cleanup(active).unwrap())
  assert_false(active.reclaimed)
  assert_true(
    @model.release_original_model_publication_capacity(capacity).unwrap(),
  )
  assert_false(
    @model.original_model_publication_capacity_current(capacity, model, scope),
  )
  let released = @resources.ledger_usage(ledger)
  assert_eq(released.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(released.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_true(
    @model.release_original_model_publication_capacity(capacity).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger), released)
  assert_true(cleanup(active).unwrap())
  assert_true(
    @model.reserve_original_model_publication_capacity(model, scope, 7L, 5L)
    is Err(@model.OutputIdentity),
  )
}

///|
test "original publication capacity exact fit and one short preserve original usage" {
  for (retained, execution) in [(7L, 5L), (6L, 5L), (7L, 4L)] {
    // Include the test filler and publication token in the synthetic census.
    // This changes no installed Run limits or normal production profile.
    let (active, _, _, _, _, _, ledger) = model_resource_park_test_start(
      max_reservations=5,
    )
    assert_true(fixture_finish(active) is Complete(_, ..))
    let limits = @resources.ledger_limits(ledger)
    let before = @resources.ledger_usage(ledger)
    // Fill the existing admitted ledger to independently chosen 7/5, 6/5 or
    // 7/4 remaining bytes. This is not a formula inferred from product work or
    // a proposed normal physical profile. No resource limits are changed.
    let filler = @resources.reserve_capacity(
      ledger,
      limits.retained_bytes -
      before.held_bytes -
      before.reserved_retention_bytes -
      retained,
      limits.execution_bytes - before.reserved_execution_bytes - execution,
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let result = @model.reserve_original_model_publication_capacity(
      active.model.unwrap(),
      active.call_scope.unwrap(),
      7L,
      5L,
    )
    if retained == 7L && execution == 5L {
      let capacity = result.unwrap()
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        before.reserved_retention_bytes + 7L,
      )
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        before.reserved_execution_bytes + 5L,
      )
      assert_true(
        @model.release_original_model_publication_capacity(capacity).unwrap(),
      )
    } else {
      if retained == 6L {
        assert_true(result is Err(@model.Ledger(@resources.RetentionLimit)))
      } else {
        assert_true(result is Err(@model.Ledger(@resources.ExecutionLimit)))
      }
      assert_eq(@resources.ledger_usage(ledger), before)
    }
    @resources.settle_capacity(ledger, filler).unwrap()
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "original publication capacity rejects foreign scope legacy Model and invalid charges" {
  let (active, _, _, _, _, _, ledger) = model_resource_park_test_start()
  let (foreign, _, _, _, _, _, _) = model_resource_park_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_true(fixture_finish(foreign) is Complete(_, ..))
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @model.reserve_original_model_publication_capacity(
      active.model.unwrap(),
      foreign.call_scope.unwrap(),
      7L,
      5L,
    )
    is Err(@model.OutputIdentity),
  )
  for (retained, execution) in [(0L, 0L), (-1L, 0L), (7L, -1L)] {
    assert_true(
      @model.reserve_original_model_publication_capacity(
        active.model.unwrap(),
        active.call_scope.unwrap(),
        retained,
        execution,
      )
      is Err(@model.InvalidLimits),
    )
  }
  assert_eq(@resources.ledger_usage(ledger), before)
  let legacy_prepared = fixture_prepared()
  let legacy_plan = call_identity_plan(legacy_prepared)
  let legacy = start(
    legacy_prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    original_funded_start_provider(Ref(0)),
    @publication_host.client_infer_plan_graph_request_cid(legacy_plan),
    standard_limits(),
    plan=Some(legacy_plan),
  ).unwrap()
  assert_true(fixture_finish(legacy) is Complete(_, ..))
  assert_true(
    @model.reserve_original_model_publication_capacity(
      legacy.model.unwrap(),
      legacy.call_scope.unwrap(),
      7L,
      5L,
    )
    is Err(@model.OutputIdentity),
  )
  assert_true(cleanup(legacy).unwrap())
  assert_true(cleanup(foreign).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "original publication capacity parked cleanup preserves exact borrow and usage" {
  let (active, original_scope, consumer, compiled, definition, plan, ledger) = model_resource_park_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let model = active.model.unwrap()
  let scope = active.call_scope.unwrap()
  let capacity = @model.reserve_original_model_publication_capacity(
    model, scope, 7L, 5L,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let park = @publication_host.park_client_model_read_consumer(
    original_scope, consumer, compiled, definition, plan,
  ).unwrap()
  for _ in 0..<2 {
    assert_true(
      @model.release_original_model_publication_capacity(capacity)
      is Err(@model.Ledger(@resources.ResourceParked)),
    )
    assert_true(
      @model.reserve_original_model_publication_capacity(model, scope, 7L, 5L)
      is Err(@model.Ledger(@resources.ResourceParked)),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_false(
      @model.original_model_publication_capacity_current(capacity, model, scope),
    )
    assert_true(
      @publication_host.client_model_resource_park_current(
        park, original_scope, compiled, definition, plan,
      )
      is Some(same) &&
      physical_equal(same, park),
    )
  }
  // No synthetic unpark or COMMIT ACK: retain the same pending borrow/custody.
}
