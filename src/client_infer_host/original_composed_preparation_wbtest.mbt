///|
// Real Common preparation/input owners with explicit synthetic byte grants.
// No installed Source/Model capacity, Account permission or physical IO is
// supplied by this fixture; provider invocation must remain zero throughout.
fn original_composed_test_input(
  prepared : @publication_host.PreparedClientProgram,
) -> (@publication_host.ClientInferOccurrence, @relation.GeneratedSequence) {
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let prefix = @input.prepare_client_composed_infer_prefix(
    prepared, occurrence, infer_fixture_registry, infer_fixture_values,
  ).unwrap()
  (occurrence, prefix)
}

///|
fn original_composed_test_release(
  ledger : @resources.Ledger,
  consumer : @publication_host.ClientModelReadConsumer,
) -> Unit raise {
  @publication_host.stop_client_model_read_consumer(consumer).unwrap()
  assert_true(
    @publication_host.settle_client_model_read_consumer(consumer, false)
    is Err(@publication_host.Resource(@resources.CleanupPending)),
  )
  @publication_host.settle_client_model_read_consumer(consumer, true).unwrap()
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "original composed entry retains one consumer through actual rows and input cleanup" {
  for
    (document, count) in [
      (infer_fixture_program, 1),
      (
        infer_fixture_program.replace(
          old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
          new="\"rows\":[]",
        ),
        0,
      ),
    ] {
    let prepared = fixture_prepared(source=document)
    let (occurrence, prefix) = original_composed_test_input(prepared)
    let plan = call_identity_plan(prepared)
    let limits = standard_limits()
    let calls = Ref(0)
    let provider = original_funded_start_provider(calls)
    let (compiled, definition, ledger, read) = original_funded_start_read(
      prepared, plan, limits,
    )
    let consumer = @publication_host.claim_client_model_read_preparation(
      read, compiled, definition, plan, 7L, 5L,
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let active = start_original_composed(
      occurrence,
      plan,
      prefix,
      [],
      provider,
      limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      100L,
      5L,
    ).unwrap()
    guard active.original_preparation.unwrap().read is Claimed(retained) else {
      abort("the original one-shot consumer must be retained")
    }
    assert_true(physical_equal(retained, consumer))
    assert_true(physical_equal(active.run_binding.unwrap().compiled, compiled))
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_eq(active.work, 0L)
    for _ in 0..<5000 {
      if active.rows is Some(_) {
        break
      }
      guard advance(active, 1).unwrap() is Continue(..) else {
        abort("composed input must reach actual rows before Model dispatch")
      }
    }
    let rows = active.rows.unwrap()
    assert_eq(@relation.prepared_infer_rows_count(rows), count)
    assert_eq(calls.val, 0)
    assert_true(cancel(active))
    assert_true(fixture_finish(active, initial_work=active.work) is Stopped(..))
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 0)
    original_composed_test_release(ledger, consumer)
  }
}

///|
test "original composed entry rejects another occurrence or plan without consuming its read" {
  let prepared = fixture_prepared()
  let (occurrence, prefix) = original_composed_test_input(prepared)
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let calls = Ref(0)
  let provider = original_funded_start_provider(calls)
  let (compiled, definition, ledger, read) = original_funded_start_read(
    prepared, plan, limits,
  )
  let consumer = @publication_host.claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  let other = fixture_prepared()
  let (foreign_occurrence, foreign_prefix) = original_composed_test_input(other)
  let foreign_plan = call_identity_plan(other)
  let before = @resources.ledger_usage(ledger)
  for
    (actual_occurrence, actual_prefix, actual_plan) in [
      (foreign_occurrence, foreign_prefix, plan),
      (occurrence, prefix, foreign_plan),
    ] {
    assert_true(
      start_original_composed(
        actual_occurrence,
        actual_plan,
        actual_prefix,
        [],
        provider,
        limits,
        compiled,
        definition,
        consumer,
        7L,
        5L,
        100L,
        5L,
      )
      is Err(OriginalCapacity(@publication_host.ForeignInput)),
    )
    assert_true(
      @publication_host.client_model_read_consumer_available(
        consumer, compiled, definition, plan, 7L, 5L,
      ),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
  }
  assert_eq(calls.val, 0)
  original_composed_test_release(ledger, consumer)
}

///|
test "original composed input failure retains the entered consumer and forbids replacement start" {
  let prepared = fixture_prepared()
  let (occurrence, prefix) = original_composed_test_input(prepared)
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let calls = Ref(0)
  let provider = original_funded_start_provider(calls)
  let (compiled, definition, ledger, read) = original_funded_start_read(
    prepared, plan, limits,
  )
  let consumer = @publication_host.claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  let other = fixture_prepared()
  let (_, foreign_prefix) = original_composed_test_input(other)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    start_original_composed(
      occurrence,
      plan,
      foreign_prefix,
      [],
      provider,
      limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      100L,
      5L,
    )
    is Err(Input(@input.UnsupportedProgram)),
  )
  // Availability retains the same live capacity for cleanup/handoff; it is
  // not the separate one-shot entry predicate. A second start still refuses.
  assert_true(
    @publication_host.client_model_read_consumer_available(
      consumer, compiled, definition, plan, 7L, 5L,
    ),
  )
  assert_true(
    start_original_composed(
      occurrence,
      plan,
      prefix,
      [],
      provider,
      limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      100L,
      5L,
    )
    is Err(
      OriginalCapacity(@publication_host.Read(@publication_host.Resource(@resources.SpentClaim))),
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(calls.val, 0)
  original_composed_test_release(ledger, consumer)
}

///|
test "original composed entry refuses an unfunded envelope before input then accepts only once" {
  let prepared = fixture_prepared()
  let (occurrence, prefix) = original_composed_test_input(prepared)
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let calls = Ref(0)
  let provider = original_funded_start_provider(calls)
  let (compiled, definition, ledger, read) = original_funded_start_read(
    prepared, plan, limits,
  )
  let consumer = @publication_host.claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    start_original_composed(
      occurrence,
      plan,
      prefix,
      [],
      provider,
      limits,
      compiled,
      definition,
      consumer,
      8L,
      5L,
      100L,
      5L,
    )
    is Err(OriginalCapacity(@publication_host.Read(_))),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    @publication_host.client_model_read_consumer_available(
      consumer, compiled, definition, plan, 7L, 5L,
    ),
  )
  let active = start_original_composed(
    occurrence,
    plan,
    prefix,
    [],
    provider,
    limits,
    compiled,
    definition,
    consumer,
    7L,
    5L,
    100L,
    5L,
  ).unwrap()
  assert_true(
    start_original_composed(
      occurrence,
      plan,
      prefix,
      [],
      provider,
      limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      100L,
      5L,
    )
    is Err(OriginalCapacity(@publication_host.Read(_))),
  )
  assert_true(cancel(active))
  assert_true(fixture_finish(active) is Stopped(..))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
  original_composed_test_release(ledger, consumer)
}
