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
    prepared,
    occurrence,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
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
      OriginalCapacity(
        @publication_host.Read(
          @publication_host.Resource(@resources.SpentClaim)
        )
      )
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

///|
// Produce and readmit actual completed-prefix evidence; these synthetic byte
// grants qualify owner/identity ordering, not physical installation or IO.
fn original_restored_composed_test_saved(
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
  custody : () -> Bool,
) -> (
  @publication_host.ClientInferSavedCallScope,
  @input.ClientInferRetainedInputExport,
) raise {
  let (input, _, scope, binding) = call_identity_fixture(prepared)
  let completed = @input.client_infer_completed_input(input).unwrap()
  let exported = @input.export_client_infer_retained_input(completed, binding).unwrap()
  let saved = @publication_host.read_client_infer_saved_call_scope(
    compiled,
    definition,
    occurrence,
    plan,
    @publication_host.client_infer_call_scope_snapshot(scope).unwrap(),
    "sha256:" + "a".repeat(64),
    custody,
  ).unwrap()
  assert_true(@input.cleanup_client_infer_input(input).unwrap())
  (saved, exported)
}

///|
test "original restored composed entry retains authenticated input on the same one-shot consumer" {
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
  let (saved, exported) = original_restored_composed_test_saved(
    prepared,
    compiled,
    definition,
    occurrence,
    plan,
    () => true,
  )
  let before = @resources.ledger_usage(ledger)
  let active = start_original_restored_composed(
    occurrence,
    plan,
    prefix,
    provider,
    @input.client_infer_retained_input_export_binding(exported),
    @input.client_infer_retained_input_export_descriptor(exported),
    @input.client_infer_retained_input_export_rows(exported),
    () => true,
    saved,
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
    abort("same original consumer required")
  }
  assert_true(physical_equal(retained, consumer))
  assert_true(physical_equal(active.saved_call_scope.unwrap(), saved))
  assert_true(physical_equal(active.run_binding.unwrap().compiled, compiled))
  assert_eq(@resources.ledger_usage(ledger), before)
  restrict_model_send_slots(active, [false]).unwrap()
  for _ in 0..<5000 {
    if active.rows is Some(_) {
      break
    }
    assert_true(advance(active, 1).unwrap() is Continue(..))
  }
  assert_eq(@relation.prepared_infer_rows_count(active.rows.unwrap()), 1)
  assert_eq(calls.val, 0)
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=active.work) is Stopped(..))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
  original_composed_test_release(ledger, consumer)
}

///|
test "original restored composed entry refuses a foreign saved Run before consuming read" {
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
  let (foreign_compiled, foreign_definition) = original_input_capacity_run(
    prepared, plan,
  )
  let (saved, exported) = original_restored_composed_test_saved(
    prepared,
    foreign_compiled,
    foreign_definition,
    occurrence,
    plan,
    () => true,
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    start_original_restored_composed(
      occurrence,
      plan,
      prefix,
      provider,
      @input.client_infer_retained_input_export_binding(exported),
      @input.client_infer_retained_input_export_descriptor(exported),
      @input.client_infer_retained_input_export_rows(exported),
      () => true,
      saved,
      limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      100L,
      5L,
    )
    is Err(CallScope(ForeignInput)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    @publication_host.client_model_read_consumer_available(
      consumer, compiled, definition, plan, 7L, 5L,
    ),
  )
  assert_eq(calls.val, 0)
  original_composed_test_release(ledger, consumer)
}

///|
test "original restored composed input refusal retains entered read without replacement or send" {
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
  let (saved, exported) = original_restored_composed_test_saved(
    prepared,
    compiled,
    definition,
    occurrence,
    plan,
    () => true,
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    start_original_restored_composed(
      occurrence,
      plan,
      prefix,
      provider,
      @input.client_infer_retained_input_export_binding(exported),
      @input.client_infer_retained_input_export_descriptor(exported),
      @input.client_infer_retained_input_export_rows(exported),
      () => false,
      saved,
      limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      100L,
      5L,
    )
    is Err(Input(_)),
  )
  assert_true(
    start_original_restored_composed(
      occurrence,
      plan,
      prefix,
      provider,
      @input.client_infer_retained_input_export_binding(exported),
      @input.client_infer_retained_input_export_descriptor(exported),
      @input.client_infer_retained_input_export_rows(exported),
      () => true,
      saved,
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
      OriginalCapacity(
        @publication_host.Read(
          @publication_host.Resource(@resources.SpentClaim)
        )
      )
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(calls.val, 0)
  original_composed_test_release(ledger, consumer)
}

///|
// Explicit original byte grants; no installed Source, permission or provider
// IO. Prior producer work remains consumed by this same one-shot input owner.
test "original composed producer work remains consumed before input and suffix progress" {
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
    prior_input_work=7L,
  ).unwrap()
  assert_eq(active.work, 7L)
  assert_eq(active.child_work, 0L)
  assert_true(execution_input_unadvanced(active))
  for _ in 0..<5000 {
    advance(active, 1).unwrap() |> ignore
    if active.work > 7L {
      break
    }
  }
  assert_true(active.work > 7L)
  assert_false(execution_input_unadvanced(active))
  assert_eq(calls.val, 0)
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=active.work) is Stopped(..))
  assert_true(cleanup(active).unwrap())
  original_composed_test_release(ledger, consumer)
}

///|
test "original composed producer work cannot renew an exhausted input allowance" {
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
      prior_input_work=limits.input.max_work.to_int64() + 1L,
    )
    is Err(InvalidAdvance),
  )
  assert_eq(calls.val, 0)
  original_composed_test_release(ledger, consumer)
}
