///|
// Independent synthetic byte grants establish ordering/custody only. They are
// not a physical allocation census, normal profile or public async admission.
fn original_funded_start_read(
  prepared : @publication_host.PreparedClientProgram,
  plan : @publication_host.ClientInferPlanGraph,
  limits : Limits,
) -> (
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
  @resources.Ledger,
  @publication_host.ClientModelReadPreparation,
) {
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  // call_identity_plan's independent contract admits four attempts and
  // 133072 transfer bytes. Match the already selected contract ceiling before
  // constructing the original Ledger; do not replace it after Model begins.
  let ledger = @resources.create_ledger({
    ..limits.model.ledger,
    attempts: Int::min(limits.model.ledger.attempts, 4),
    transfer_bytes: Int64::min(limits.model.ledger.transfer_bytes, 133072L),
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 4, 2, 0,
  ).unwrap()
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  (compiled, definition, ledger, read)
}

///|
fn original_funded_start_provider(calls : Ref[Int]) -> @model.ModelProvider {
  @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Ok({
      value: @admitted.object_value([
        ("reason", @admitted.null_value()),
        ("risk", @admitted.text_value("high", 100).unwrap()),
      ]).unwrap(),
      provider_model: "fixture",
      provider_request_id: "request-" + calls.val.to_string(),
      input_tokens: 1L,
      output_tokens: 2L,
      observed_at: "2026-10-02T00:00:00.000Z",
    })
  }).unwrap()
}

///|
fn original_funded_start_from_read(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry : @input.ClientInstalledSequenceContracts,
  values : String,
  provider : @model.ModelProvider,
  limits : Limits,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  read : @publication_host.ClientModelReadPreparation,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
) -> Result[Execution, Issue] {
  let consumer = match
    @publication_host.claim_client_model_read_preparation(
      read, compiled, definition, plan, read_retained_bytes, read_execution_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(OriginalCapacity(@publication_host.Read(issue)))
  }
  start_original_model_preparation(
    prepared, step, registry, values, provider, limits, compiled, definition, plan,
    consumer, read_retained_bytes, read_execution_bytes, model_retained_bytes, model_execution_bytes,
  )
}

///|
test "original funded start refuses envelope before input and retains same read" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let calls = Ref(0)
  let provider = original_funded_start_provider(calls)
  let (compiled, definition, ledger, read) = original_funded_start_read(
    prepared, plan, limits,
  )
  let before = @resources.ledger_usage(ledger)
  let quantities = @resources.quantity_usage(ledger)
  for
    (retention, execution, expected) in [
      (8L, 5L, @resources.RetentionLimit),
      (7L, 6L, @resources.ExecutionLimit),
    ] {
    // Malformed input would fail in the old start-before-bind path. The exact
    // original token guard must refuse first without creating an input owner.
    assert_true(
      original_funded_start_from_read(
        prepared,
        2,
        infer_fixture_installed_contracts(),
        "not JSON",
        provider,
        limits,
        compiled,
        definition,
        plan,
        read,
        retention,
        execution,
        100L,
        5L,
      )
      is Err(
        OriginalCapacity(
          @publication_host.Read(
            @publication_host.Resource(@resources.Resource(actual))
          )
        )
      ) &&
      actual == expected,
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_eq(@resources.quantity_usage(ledger), quantities)
    assert_true(
      @publication_host.client_model_read_available(
        read, compiled, definition, plan,
      ),
    )
  }
  let active = original_funded_start_from_read(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    provider,
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
  assert_eq(active.work, 0L)
  assert_true(active.original_preparation.unwrap().read is Claimed(_))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(cancel(active))
  assert_true(fixture_finish(active) is Stopped(..))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
  original_preparation_test_release(ledger, read)
}

///|
test "original funded start rejects different prepared occurrence and spent read" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let calls = Ref(0)
  let provider = original_funded_start_provider(calls)
  let (compiled, definition, ledger, read) = original_funded_start_read(
    prepared, plan, limits,
  )
  let other = fixture_prepared()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    original_funded_start_from_read(
      other,
      2,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
      provider,
      limits,
      compiled,
      definition,
      plan,
      read,
      7L,
      5L,
      100L,
      5L,
    )
    is Err(OriginalCapacity(@publication_host.ForeignInput)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @publication_host.stop_client_model_read(read).unwrap()
  assert_false(
    original_model_preparation_available(
      read, compiled, definition, plan, 7L, 5L,
    ),
  )
  assert_true(
    original_funded_start_from_read(
      prepared,
      2,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
      provider,
      limits,
      compiled,
      definition,
      plan,
      read,
      7L,
      5L,
      100L,
      5L,
    )
    is Err(OriginalCapacity(_)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(calls.val, 0)
  original_preparation_test_release(ledger, read)
}

///|
test "original funded start used seal retains same Ledger through output release" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let calls = Ref(0)
  let provider = original_funded_start_provider(calls)
  let (compiled, definition, ledger, read) = original_funded_start_read(
    prepared, plan, limits,
  )
  let active = original_funded_start_from_read(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    provider,
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
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 1)
  assert_eq(
    @model.model_execution_resource_usage(active.model.unwrap()),
    @resources.ledger_usage(ledger),
  )
  let seal = active.original_preparation.unwrap().startup.unwrap()
  let output_use = acquire_output(active).unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_false(cleanup(active).unwrap())
  assert_eq(@resources.ledger_usage(ledger), held)
  assert_false(@model.cleanup_original_model_startup(seal).unwrap())
  assert_true(release_output(output_use))
  assert_true(cleanup(active).unwrap())
  assert_true(@model.cleanup_original_model_startup(seal).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  let retired = @resources.ledger_usage(ledger)
  assert_true(cleanup(active).unwrap())
  assert_eq(@resources.ledger_usage(ledger), retired)
  original_preparation_test_release(ledger, read)
}

///|
test "original funded start cannot allocate twice from the same early read grant" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let calls = Ref(0)
  let provider = original_funded_start_provider(calls)
  let (compiled, definition, ledger, read) = original_funded_start_read(
    prepared, plan, limits,
  )
  let first = original_funded_start_from_read(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    provider,
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
  let before = @resources.ledger_usage(ledger)
  let second = original_funded_start_from_read(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    provider,
    limits,
    compiled,
    definition,
    plan,
    read,
    7L,
    5L,
    100L,
    5L,
  )
  let duplicated = second is Ok(_)
  // Retire both possible original children before reporting this counterexample.
  // A late handoff refusal cannot account for their earlier simultaneous roots.
  if second is Ok(other) {
    assert_eq(other.work, 0L)
    assert_true(cancel(other))
    assert_true(fixture_finish(other) is Stopped(..))
    assert_true(cleanup(other).unwrap())
  }
  assert_eq(first.work, 0L)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(calls.val, 0)
  assert_true(cancel(first))
  assert_true(fixture_finish(first) is Stopped(..))
  assert_true(cleanup(first).unwrap())
  original_preparation_test_release(ledger, read)
  assert_false(duplicated)
}

///|
test "original funded start aliased consumer enters once and keeps original read cleanup" {
  let prepared = fixture_prepared()
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
  let quantities = @resources.quantity_usage(ledger)
  let active = start_original_model_preparation(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    provider,
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
  assert_true(
    active.original_preparation.unwrap().read is Claimed(actual) &&
    physical_equal(actual, consumer),
  )
  // The malformed input would prove a second input owner was constructed.
  assert_true(
    start_original_model_preparation(
      prepared,
      2,
      infer_fixture_installed_contracts(),
      "not JSON",
      provider,
      limits,
      compiled,
      definition,
      plan,
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
  assert_true(
    @publication_host.claim_client_model_read_preparation(
      read, compiled, definition, plan, 7L, 5L,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  assert_eq(active.work, 0L)
  assert_eq(calls.val, 0)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  assert_true(cancel(active))
  assert_false(
    @publication_host.client_model_read_consumer_available(
      consumer, compiled, definition, plan, 7L, 5L,
    ),
  )
  assert_true(fixture_finish(active) is Stopped(..))
  assert_true(cleanup(active).unwrap())
  // Core cleanup is not original read/FD/Store cleanup. Its reservation remains.
  assert_eq(@resources.ledger_usage(ledger), before)
  original_preparation_test_release(ledger, read)
  assert_false(
    @publication_host.client_model_read_consumer_available(
      consumer, compiled, definition, plan, 7L, 5L,
    ),
  )
}

///|
test "original funded start input refusal spends same ticket without losing original custody" {
  let prepared = fixture_prepared()
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
    start_original_model_preparation(
      prepared,
      2,
      infer_fixture_installed_contracts(),
      "not JSON",
      provider,
      limits,
      compiled,
      definition,
      plan,
      consumer,
      7L,
      5L,
      100L,
      5L,
    )
    is Err(Input(_)),
  )
  assert_true(
    start_original_model_preparation(
      prepared,
      2,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
      provider,
      limits,
      compiled,
      definition,
      plan,
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
  assert_eq(calls.val, 0)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    @publication_host.settle_client_model_read(read, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  original_preparation_test_release(ledger, read)
}

///|
test "original funded start failed Model retains unused seal through input cleanup" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let calls = Ref(0)
  let provider = original_funded_start_provider(calls)
  let (compiled, definition, ledger, read) = original_funded_start_read(
    prepared,
    plan,
    {
      ..limits,
      model: {
        ..limits.model,
        ledger: {
          ..limits.model.ledger,
          planning_work: limits.model.ledger.planning_work - 1,
        },
      },
    },
  )
  let active = original_funded_start_from_read(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    provider,
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
  while active.rows is None {
    assert_true(advance(active, 1).unwrap() is Continue(..))
  }
  let input_use = @relation.acquire_prepared_infer_rows(active.rows.unwrap()).unwrap()
  assert_true(
    fixture_finish(active, initial_work=active.work)
    is Failed(Model(@model.RequestIdentity), ..),
  )
  let preparation = active.original_preparation.unwrap()
  let seal = preparation.startup.unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_false(cleanup(active).unwrap())
  assert_true(physical_equal(active.original_preparation.unwrap(), preparation))
  assert_eq(@resources.ledger_usage(ledger), held)
  assert_false(@model.cleanup_original_model_startup(seal).unwrap())
  assert_true(@relation.release_prepared_infer_rows_use(input_use))
  assert_true(cleanup(active).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(@model.cleanup_original_model_startup(seal).unwrap())
  assert_eq(calls.val, 0)
  original_preparation_test_release(ledger, read)
}
