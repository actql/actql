///|
test "original scope quantity ceilings agree with the later original startup" {
  for
    (tokens, cost, duration) in [
      (10000L, 10000L, 10000L),
      (128L, 0L, 1000L),
      (66L, 0L, 500L),
    ] {
    let prepared = fixture_prepared()
    let plan = call_identity_plan(prepared)
    let (compiled, definition) = original_input_capacity_run(prepared, plan)
    let limits = standard_limits()
    let installed : @model.ModelQuantityCapacity = {
      limits: { tokens, cost_units: cost, duration_ms: duration, },
      per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
    }
    let scope = begin_original_model_read_scope(
      compiled,
      definition,
      plan,
      limits.model,
      Some(installed),
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
    bind_quantity_capacity(active, installed).unwrap()
    let terminal = fixture_finish(active)
    if terminal is Failed(Model(@model.RequestIdentity), ..) {
      // Retain the typed first failure in the bounded diagnostic output.
      println("original startup refusal: Model(RequestIdentity)")
    }
    assert_true(terminal is Complete(_, ..))
    assert_eq(calls.val, 1)
    let usage = execution_quantity_usage(active).unwrap()
    assert_eq(usage.consumed.tokens, 3L)
    assert_eq(usage.consumed.cost_units, 0L)
    assert_eq(usage.uncertain.duration_ms, 500L)
    assert_true(cleanup(active).unwrap())
    @publication_host.settle_client_model_read(read, true).unwrap()
    assert_true(
      @publication_host.finish_client_model_read_scope(
        scope, compiled, definition, plan, true,
      ).unwrap(),
    )
    assert_eq(execution_quantity_usage(active).unwrap(), usage)
    assert_eq(calls.val, 1)
  }
}

///|
test "original scope quantity configuration never widens smaller installed ceilings" {
  for
    (tokens, cost, duration, expected_tokens, expected_cost, expected_duration) in [
      (10000L, 10000L, 10000L, 128L, 0L, 1000L),
      (128L, 0L, 1000L, 128L, 0L, 1000L),
      (66L, 0L, 500L, 66L, 0L, 500L),
    ] {
    let prepared = fixture_prepared()
    let plan = call_identity_plan(prepared)
    let (compiled, definition) = original_input_capacity_run(prepared, plan)
    let installed : @model.ModelQuantityCapacity = {
      limits: { tokens, cost_units: cost, duration_ms: duration, },
      per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
    }
    let scope = begin_original_model_read_scope(
      compiled,
      definition,
      plan,
      standard_limits().model,
      Some(installed),
      3L,
      2L,
      4,
      2,
      0,
    ).unwrap()
    let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
    // Existing test observation; no production Ledger getter is introduced.
    let ledger = @publication_host.handoff_client_model_read(
      read, compiled, definition, plan,
    ).unwrap()
    assert_true(
      @resources.quantity_configuration_matches(
        ledger,
        Some({
          tokens: expected_tokens,
          cost_units: expected_cost,
          duration_ms: expected_duration,
        }),
      ),
    )
    assert_eq(@resources.quantity_usage(ledger).consumed.tokens, 0L)
    assert_eq(@resources.ledger_usage(ledger).attempts, 0)
    original_preparation_test_release(ledger, read)
  }
}

///|
test "original scope quantity rejects invalid installed quantities before bootstrap" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let valid : @model.ModelQuantityCapacity = {
    limits: { tokens: 66L, cost_units: 0L, duration_ms: 1000L, },
    per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
  }
  for
    invalid in [
      { ..valid, limits: { ..valid.limits, tokens: -1L, }, },
      { ..valid, limits: { ..valid.limits, cost_units: -1L, }, },
      { ..valid, limits: { ..valid.limits, duration_ms: -1L, }, },
      { ..valid, per_attempt: { ..valid.per_attempt, tokens: -1L, }, },
      { ..valid, per_attempt: { ..valid.per_attempt, cost_units: -1L, }, },
      { ..valid, per_attempt: { ..valid.per_attempt, duration_ms: -1L, }, },
      {
        ..valid,
        per_attempt: { ..valid.per_attempt, tokens: 9007199254740992L, },
      },
      {
        ..valid,
        per_attempt: { ..valid.per_attempt, cost_units: 9007199254740992L, },
      },
      {
        ..valid,
        per_attempt: { ..valid.per_attempt, duration_ms: 9007199254740992L, },
      },
    ] {
    assert_true(
      begin_original_model_read_scope(
        compiled,
        definition,
        plan,
        standard_limits().model,
        Some(invalid),
        0L,
        0L,
        0,
        0,
        0,
      )
      is Err(Model(@model.InvalidLimits)),
    )
  }
}

///|
// Real portable composed input/Scope/Model owners; the supplied physical
// provider and byte envelopes remain explicit component fixtures.
test "shared provider starts with the same effective quantity configuration and never resets its parent" {
  let declarations : Array[@resources.QuantityAmounts] = [
    { tokens: 10000L, cost_units: 10000L, duration_ms: 10000L, },
    { tokens: 66L, cost_units: 0L, duration_ms: 500L, },
  ]
  for installed_limits in declarations {
    let prepared = fixture_prepared()
    let plan = call_identity_plan(prepared)
    let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
      prepared,
    ).unwrap()
    let (compiled, definition) = original_input_capacity_run(prepared, plan)
    let limits = standard_limits()
    let installed : @model.ModelQuantityCapacity = {
      limits: installed_limits,
      per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
    }
    let effective = original_model_quantity_capacity(plan, installed).unwrap()
    let model_limits = original_model_ledger_limits(plan, limits.model)
    let parent_limits = @resources.add_ledger_limits(model_limits, {
      planning_work: 17,
      attempts: 0,
      holdings: 1,
      transfer_bytes: 0L,
      retained_bytes: 1000L,
      execution_bytes: 1000L,
    }).unwrap()
    let ledger = @resources.create_ledger(parent_limits).unwrap()
    @resources.configure_quantities(ledger, effective.limits).unwrap()
    let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
    let scope = @publication_host.begin_client_model_read_scope(
      compiled, definition, plan, ledger, bootstrap, 8, 2, 0,
    ).unwrap()
    let sibling = @resources.reserve_capacity(ledger, 20L, 10L).unwrap()
    let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
    let consumer = @publication_host.claim_client_model_read_preparation(
      read, compiled, definition, plan, 7L, 5L,
    ).unwrap()
    let prefix = @input.prepare_client_composed_infer_prefix(
      prepared,
      occurrence,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
    ).unwrap()
    let calls = Ref(0)
    let active = start_original_composed(
      occurrence,
      plan,
      prefix,
      [],
      original_funded_start_provider(calls),
      limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      100L,
      5L,
    ).unwrap()
    // The ordinary late binder receives the ORIGINAL installed declaration;
    // its same execution-contract intersection must match the early parent.
    bind_quantity_capacity(active, installed).unwrap()
    assert_true(
      @resources.quantity_configuration_matches(
        ledger,
        Some(active.quantity_capacity.unwrap().limits),
      ),
    )
    assert_eq(active.quantity_capacity.unwrap().limits, effective.limits)
    assert_true(fixture_finish(active) is Complete(_, ..))
    assert_eq(calls.val, 1)
    let usage = execution_quantity_usage(active).unwrap()
    assert_eq(usage.consumed.tokens, 3L)
    assert_eq(usage.uncertain.duration_ms, 500L)
    assert_true(cleanup(active).unwrap())
    assert_eq(@resources.quantity_usage(ledger), usage)
    assert_true(@resources.capacity_reservation_open(sibling))
    @publication_host.settle_client_model_read(read, true).unwrap()
    assert_true(
      @resources.finish_original_ledger_inventory(ledger, true) is Ok(false),
    )
    @resources.settle_capacity(ledger, sibling).unwrap()
    assert_true(
      @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
    )
    assert_eq(@resources.quantity_usage(ledger), usage)
  }
}
