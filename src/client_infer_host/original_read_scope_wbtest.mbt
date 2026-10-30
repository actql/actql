///|
test "original read scope configures quantities and checked ceilings before read" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let limits = standard_limits().model
  let quantity = fixture_quantity_capacity(66L, 1000L)
  let scope = begin_original_model_read_scope(
    compiled,
    definition,
    plan,
    limits,
    Some(quantity),
    3L,
    2L,
    4,
    2,
    0,
  ).unwrap()
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  // Existing nominal test observation, not a new production Ledger getter.
  let ledger = @publication_host.handoff_client_model_read(
    read, compiled, definition, plan,
  ).unwrap()
  let actual_limits = @resources.ledger_limits(ledger)
  assert_eq(actual_limits.attempts, 4)
  assert_eq(actual_limits.transfer_bytes, 133072L)
  assert_eq(actual_limits.retained_bytes, limits.ledger.retained_bytes)
  assert_eq(actual_limits.execution_bytes, limits.ledger.execution_bytes)
  assert_true(
    @resources.quantity_configuration_matches(ledger, Some(quantity.limits)),
  )
  let actual = @resources.ledger_usage(ledger)
  assert_eq(actual.reserved_retention_bytes, 10L)
  assert_eq(actual.reserved_execution_bytes, 7L)
  assert_eq(actual.attempts, 0)
  assert_eq(@resources.quantity_usage(ledger).consumed.tokens, 0L)
  assert_true(
    @resources.configure_quantities(ledger, quantity.limits)
    is Err(@resources.InvalidCharge),
  )
  original_preparation_test_release(ledger, read)
}

///|
test "actual original Model startup retains preparation input and configured quantities on the same parent" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let limits = standard_limits()
  let quantity = original_model_quantity_capacity(
    plan,
    fixture_quantity_capacity(66L, 1000L),
  ).unwrap()
  let ledger = @resources.create_ledger(
    original_model_ledger_limits(plan, limits.model),
  ).unwrap()
  let input = [1]
  // Original compiled/Scope/Model consumers with explicit logical Resource
  // frames; these small values are not a physical installed Model recipe.
  let parent : @resources.PreparationCapacity[
    Array[Int],
    @publication_host.PreparedClientProgram,
  ] = @resources.reserve_preparation_capacity_inventory(
    ledger,
    input,
    3L,
    0L,
    max_borrowers=4,
  ).unwrap()
  let identity = @resources.preparation_capacity_inventory_original(
    parent, input,
  ).unwrap()
  let operation = @resources.begin_preparation_io(parent, input, 3L).unwrap()
  @resources.charge_preparation_io(operation, 2L).unwrap()
  @resources.finish_preparation_io_after_cleanup(operation).unwrap()
  @resources.charge_planning(ledger, 1).unwrap()
  let before = @resources.ledger_usage(ledger)
  @resources.configure_quantities(ledger, quantity.limits).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  @resources.grow_preparation_capacity_inventory(parent, input, 3L, 2L, 4, 2, 0).unwrap()
  let scope = @publication_host.bind_client_model_read_scope(
    compiled, definition, plan, ledger, identity,
  ).unwrap()
  @resources.complete_preparation_capacity(parent, input, prepared, 3L, 2L).unwrap()
  let held = @resources.borrow_preparation_body(parent).unwrap()
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  let calls = Ref(0)
  let active = original_funded_start_from_read(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    original_funded_start_provider(calls),
    limits,
    compiled,
    definition,
    plan,
    read,
    7L,
    5L,
    100L,
    5L,
  ).unwrap()
  bind_quantity_capacity(active, quantity).unwrap()
  assert_eq(calls.val, 0)
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 1)
  assert_eq(
    @model.model_execution_quantity_usage(active.model.unwrap()).consumed.tokens,
    3L,
  )
  assert_true(cleanup(active).unwrap())
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_false(
    @publication_host.finish_client_model_read_inventory(
      read, compiled, definition, plan, false,
    ).unwrap(),
  )
  assert_true(
    @publication_host.finish_client_model_read_inventory(
      read, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_false(@resources.retire_preparation_capacity(parent).unwrap())
  assert_true(
    @resources.preparation_body_borrow_value(held) is Some(original) &&
    physical_equal(original, prepared),
  )
  assert_true(@resources.return_preparation_body_borrow(held).unwrap())
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_true(@resources.ledger_usage(ledger).attempts > 1)
  assert_true(@resources.ledger_usage(ledger).transferred_bytes >= 2L)
  assert_true(@resources.ledger_usage(ledger).planning_work >= 1)
  assert_eq(@resources.quantity_usage(ledger).consumed.tokens, 3L)
  assert_true(
    @resources.quantity_configuration_matches(ledger, Some(quantity.limits)),
  )
}

///|
test "original read scope reaches Model through the same configured Ledger" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let limits = standard_limits()
  let quantity = fixture_quantity_capacity(66L, 1000L)
  let scope = begin_original_model_read_scope(
    compiled,
    definition,
    plan,
    limits.model,
    Some(quantity),
    3L,
    2L,
    4,
    2,
    0,
  ).unwrap()
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  let calls = Ref(0)
  let active = original_funded_start_from_read(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    original_funded_start_provider(calls),
    limits,
    compiled,
    definition,
    plan,
    read,
    7L,
    5L,
    100L,
    5L,
  ).unwrap()
  bind_quantity_capacity(active, quantity).unwrap()
  assert_eq(calls.val, 0)
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 1)
  assert_eq(
    @model.model_execution_quantity_usage(active.model.unwrap()).consumed.tokens,
    3L,
  )
  assert_true(cleanup(active).unwrap())
  @publication_host.settle_client_model_read(read, true).unwrap()
  // Child cleanup and the original Run acknowledgement remain separate.
  assert_false(
    @publication_host.finish_client_model_read_inventory(
      read, compiled, definition, plan, false,
    ).unwrap(),
  )
  assert_true(
    @publication_host.finish_client_model_read_inventory(
      read, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_false(
    @publication_host.client_model_read_available(
      read, compiled, definition, plan,
    ),
  )
  assert_eq(calls.val, 1)
}

///|
test "original read scope keeps failed read custody until original cleanup" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let base = standard_limits().model
  let limits : @model.ModelExecutionLimits = {
    ..base,
    ledger: { ..base.ledger, retained_bytes: 9L, execution_bytes: 7L, },
  }
  let scope = begin_original_model_read_scope(
    compiled,
    definition,
    plan,
    limits,
    None,
    3L,
    2L,
    4,
    2,
    0,
  ).unwrap()
  assert_true(
    @publication_host.prepare_client_model_read(scope, 7L, 5L)
    is Err(
      @publication_host.Resource(@resources.Resource(@resources.RetentionLimit))
    ),
  )
  // No preparation exists, but the original scope still owns bootstrap.
  assert_false(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, false,
    ).unwrap(),
  )
  assert_true(
    @publication_host.prepare_client_model_read(scope, 7L, 5L)
    is Err(@publication_host.Resource(@resources.IncompleteInventory)),
  )
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    )
    is Err(@publication_host.Resource(@resources.SpentClaim)),
  )
}

///|
test "original read scope refuses invalid bootstrap and foreign originals without IO" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let other = fixture_prepared(
    source=infer_fixture_program.replace(old="hello", new="different"),
  )
  let (foreign, foreign_definition) = original_input_capacity_run(
    other,
    call_identity_plan(other),
  )
  let limits = standard_limits().model
  assert_true(
    begin_original_model_read_scope(
      compiled,
      foreign_definition,
      plan,
      limits,
      None,
      3L,
      2L,
      4,
      2,
      0,
    )
    is Err(
      OriginalCapacity(@publication_host.Read(@publication_host.ForeignRun))
    ),
  )
  assert_true(
    begin_original_model_read_scope(
      foreign,
      definition,
      plan,
      limits,
      None,
      3L,
      2L,
      4,
      2,
      0,
    )
    is Err(
      OriginalCapacity(@publication_host.Read(@publication_host.ForeignRun))
    ),
  )
  assert_true(
    begin_original_model_read_scope(
      compiled,
      definition,
      plan,
      limits,
      None,
      0L,
      2L,
      4,
      2,
      0,
    )
    is Err(
      OriginalCapacity(
        @publication_host.Read(@publication_host.InvalidBootstrap)
      )
    ),
  )
  assert_true(
    begin_original_model_read_scope(
      compiled,
      definition,
      plan,
      limits,
      None,
      limits.ledger.retained_bytes + 1L,
      2L,
      4,
      2,
      0,
    )
    is Err(Model(@model.Ledger(@resources.RetentionLimit))),
  )
}
