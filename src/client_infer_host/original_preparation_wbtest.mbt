///|
// Independent synthetic grants test the original caller and custody, not a
// physical byte census, adopted normal profile or durable Store authentication.
fn original_preparation_test_read(
  active : Execution,
  ledger_limits? : @resources.LedgerLimits = active.limits.model.ledger,
  reservation_slots? : Int = 4,
  spent_planning? : Bool = false,
  quantities? : @resources.QuantityAmounts? = None,
) -> (@resources.Ledger, @publication_host.ClientModelReadPreparation) {
  let (compiled, definition) = invocation_fixture_compiled(active)
  let ledger = @resources.create_ledger(ledger_limits).unwrap()
  if quantities is Some(amounts) {
    @resources.configure_quantities(ledger, amounts).unwrap()
  }
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled,
    definition,
    active.plan.unwrap(),
    ledger,
    bootstrap,
    reservation_slots,
    2,
    0,
  ).unwrap()
  // Admit the original cumulative spend in its descriptor, not by mutating
  // the authenticated read snapshot after it has already been issued.
  if spent_planning {
    @resources.charge_planning(ledger, ledger_limits.planning_work).unwrap()
  }
  (ledger, @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap())
}

///|
fn original_preparation_test_release(
  ledger : @resources.Ledger,
  read : @publication_host.ClientModelReadPreparation,
) -> Unit raise {
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "original preparation actual Identity keeps same Ledger and Model owns used seal cleanup" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  let (ledger, read) = original_preparation_test_read(active, spent_planning=true)
  let quantities = @resources.quantity_usage(ledger)
  bind_original_model_preparation(active, read, 100L, 5L).unwrap()
  while active.model is None {
    guard advance(active, 1).unwrap() is Continue(..) else {
      abort("normal prefix and Identity must reach original Model startup")
    }
  }
  assert_eq(calls.val, 0)
  assert_true(active.call_scope is Some(_))
  assert_true(active.original_preparation.unwrap().startup is Some(_))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 110L)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  let model = active.model.unwrap()
  assert_eq(
    @model.model_execution_resource_usage(model),
    @resources.ledger_usage(ledger),
  )
  let terminal = fixture_finish(active, initial_work=active.work)
  if terminal is Failed(Model(issue), ..) {
    assert_eq(Some(issue), None)
  }
  assert_true(terminal is Complete(_, ..))
  assert_eq(calls.val, 2)
  assert_eq(@resources.ledger_usage(ledger).planning_work, active.limits.model.ledger.planning_work)
  let output_use = acquire_output(active).unwrap()
  assert_false(cleanup(active).unwrap())
  // Original 3+7+100 plus two independent 1000+65536 attempt envelopes.
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 133182L)
  assert_true(release_output(output_use))
  assert_true(cleanup(active).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  let after = @resources.ledger_usage(ledger)
  assert_true(cleanup(active).unwrap())
  assert_eq(@resources.ledger_usage(ledger), after)
  assert_eq(calls.val, 2)
  original_preparation_test_release(ledger, read)
}

///|
test "original preparation refused start retains unused seal until exact input cleanup" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  // A different installed Ledger limit is not repaired by reissuing a Ledger.
  let (ledger, read) = original_preparation_test_read(active, ledger_limits={
    ..active.limits.model.ledger,
    planning_work: active.limits.model.ledger.planning_work - 1,
  })
  bind_original_model_preparation(active, read, 100L, 5L).unwrap()
  while active.rows is None {
    guard advance(active, 1).unwrap() is Continue(..) else {
      abort("the actual prefix must prepare original rows")
    }
  }
  let rows = active.rows.unwrap()
  let input_use = @relation.acquire_prepared_infer_rows(rows).unwrap()
  assert_true(
    fixture_finish(active, initial_work=active.work)
    is Failed(Model(@model.RequestIdentity), ..),
  )
  assert_eq(calls.val, 0)
  assert_true(active.model is None)
  let preparation = active.original_preparation.unwrap()
  let seal = preparation.startup.unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 110L)
  assert_false(@model.cleanup_original_model_startup(seal).unwrap())
  assert_false(cleanup(active).unwrap())
  assert_true(physical_equal(active.original_preparation.unwrap(), preparation))
  assert_true(physical_equal(preparation.startup.unwrap(), seal))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 110L)
  assert_true(@relation.release_prepared_infer_rows_use(input_use))
  assert_true(cleanup(active).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(@model.cleanup_original_model_startup(seal).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_eq(calls.val, 0)
  original_preparation_test_release(ledger, read)
}

///|
test "original preparation grant refusal preserves original read without an escaped seal" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  let (ledger, read) = original_preparation_test_read(active)
  let before = @resources.ledger_usage(ledger)
  bind_original_model_preparation(
    active,
    read,
    active.limits.model.ledger.retained_bytes + 1L,
    5L,
  ).unwrap()
  assert_true(fixture_finish(active) is Failed(OriginalCapacity(_), ..))
  assert_true(active.original_preparation.unwrap().startup is None)
  assert_eq(@resources.ledger_usage(ledger), before)
  let bound = active.run_binding.unwrap()
  assert_true(
    @publication_host.client_model_read_available(
      read,
      bound.compiled,
      bound.definition,
      active.plan.unwrap(),
    ),
  )
  assert_eq(calls.val, 0)
  assert_true(cleanup(active).unwrap())
  original_preparation_test_release(ledger, read)
}

///|
test "original preparation rejects foreign and repeated binding before any handoff" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  let other = contract_capacity_start(calls, 2, 133072L)
  let (ledger, read) = original_preparation_test_read(other)
  invocation_fixture_compiled(active) |> ignore
  let before = @resources.ledger_usage(ledger)
  assert_true(
    bind_original_model_preparation(active, read, 100L, 5L)
    is Err(OriginalCapacity(_)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  bind_original_model_preparation(other, read, 100L, 5L).unwrap()
  assert_true(
    bind_original_model_preparation(other, read, 100L, 5L)
    is Err(InvalidAdvance),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(cancel(other))
  assert_true(fixture_finish(other) is Stopped(..))
  assert_true(cleanup(other).unwrap())
  assert_true(cancel(active))
  assert_true(fixture_finish(active) is Stopped(..))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
  original_preparation_test_release(ledger, read)
}

///|
test "original preparation exhausted token inventory refuses before send and retains cleanup" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  // Two records hold read and seal, leaving no record for a physical attempt.
  // Keep this independent refusal: spare bytes do not create inventory slots.
  let (ledger, read) = original_preparation_test_read(active, reservation_slots=2)
  bind_original_model_preparation(active, read, 100L, 5L).unwrap()
  assert_true(
    fixture_finish(active)
    is Failed(Model(@model.Ledger(@resources.RetentionLimit)), ..),
  )
  assert_eq(calls.val, 0)
  assert_true(active.model is Some(_))
  let seal = active.original_preparation.unwrap().startup.unwrap()
  assert_false(@model.cleanup_original_model_startup(seal).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 110L)
  assert_true(cleanup(active).unwrap())
  assert_true(@model.cleanup_original_model_startup(seal).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  original_preparation_test_release(ledger, read)
}

///|
test "original preparation keeps all prepared rows for full and partial false masks" {
  for mask in [[false, false], [true, false]] {
    let calls = Ref(0)
    let active = contract_capacity_start(calls, 2, 133072L)
    let (ledger, read) = original_preparation_test_read(active)
    active.durable_calls = true
    active.model_send_mask = Some(mask)
    bind_original_model_preparation(active, read, 100L, 5L).unwrap()
    while active.model is None {
      guard advance(active, 1).unwrap() is Continue(..) else {
        abort("all admitted rows must reach original startup before a send")
      }
    }
    assert_eq(@relation.prepared_infer_rows_count(active.rows.unwrap()), 2)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 110L)
    assert_true(cancel(active))
    assert_true(fixture_finish(active, initial_work=active.work) is Stopped(..))
    assert_eq(calls.val, 0)
    assert_true(cleanup(active).unwrap())
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
    original_preparation_test_release(ledger, read)
  }
}
