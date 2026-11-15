///|
// Actual checked129 Model prefix/export/saved scope and numerical Read. The
// provider and byte grants are explicit fixtures, not ordinary Store/runtime.
fn original_129_restore_read(
  fresh : Execution,
  retained : Int64,
) -> (
  @resources.Ledger,
  @publication_host.ClientModelReadPreparation,
  @publication_host.ClientModelReadConsumer,
) {
  let bound = fresh.run_binding.unwrap()
  let ledger = @resources.create_ledger({
    ..fresh.limits.model.ledger,
    retained_bytes: retained,
    execution_bytes: 67108864L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    bound.compiled,
    bound.definition,
    fresh.plan.unwrap(),
    ledger,
    bootstrap,
    1024,
    260,
    0,
  ).unwrap()
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  let consumer = @publication_host.claim_client_model_read_preparation(
    read,
    bound.compiled,
    bound.definition,
    fresh.plan.unwrap(),
    7L,
    5L,
  ).unwrap()
  (ledger, read, consumer)
}

///|
fn original_129_restoring_prefix(
  fresh : Execution,
) -> @relation.GeneratedSequence raise {
  let limits = {
    ..@publication_host.client_standard_values_sequence_limits(),
    max_rows: 129,
  }
  let owner = @publication_host.client_infer_occurrence_preparation(
    fresh.occurrence,
  )
  let semantic = @lower.prepare_sequence_prefix(owner, 1, limits).unwrap()
  let contracts = @relation.admit_relation_registry(
    @canonical.from_json(
      @json.parse(infer_fixture_registry),
      10000,
      100,
      100000,
    ),
    @canonical.from_json(@json.parse(infer_fixture_values), 10000, 100, 100000),
    { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
  ).unwrap()
  let retained = @lower.node_id(
    @lower.node_at(@lower.bound_preparation(owner), 1).unwrap(),
  )
  @relation.prepare_generated_sequence(
    contracts,
    semantic,
    [],
    [retained],
    100000,
    10000,
  ).unwrap()
}

///|
test "original129 retained input roundtrip keeps legacy100 and foreign current small budget guards" {
  let (fresh, fresh_ledger, fresh_consumer, fresh_calls) = original_129_snapshot_fixture()
  // A flat two-column relation has depth2 regardless of its row count. The
  // content identity tuple's fourth field is rows, never an encoding depth.
  let receipt = @relation.completed_relation_identity_scan_body_receipt(
    fresh.identity.unwrap(),
  ).unwrap()
  let geometry = @relation.completed_relation_export_scalar_geometry(receipt)
  assert_eq(geometry.0, 129)
  assert_eq(geometry.3, 2)
  let prepared = prepared_call_set(fresh).unwrap()
  let input = @model.prepared_model_input(prepared).unwrap()
  assert_true(
    @input.export_client_infer_retained_input(input, "same-binding") is Err(_),
  )
  let bound = fresh.run_binding.unwrap()
  let boundary = @publication_host.client_infer_plan_boundary(
    fresh.plan.unwrap(),
  )
  let binding = fixture_canonical({
    "version": "actql-model-fixed-input-binding/0.1",
    "run_definition_cid": @publication.publication_contract_identity(
      bound.definition,
    ),
    "scope_cid": "sha256:" + "c".repeat(64),
    "input_artifact_cid": @publication.run_evidence_value_identity(
      @publication_host.client_infer_call_scope_artifact(
        fresh.call_scope.unwrap(),
      ),
    ),
    "task_index": boundary.0,
    "strategy_revision": boundary.2,
  })
  let exported = export_prepared_input(fresh, prepared, binding).unwrap()
  let rows = @input.client_infer_retained_input_export_rows(exported)
  assert_eq(rows.length(), 129)
  let descriptor = @input.client_infer_retained_input_export_descriptor(
    exported,
  )
  let prefix = original_129_restoring_prefix(fresh)
  let current = Ref(true)
  let saved = @publication_host.read_client_infer_saved_call_scope(
    bound.compiled,
    bound.definition,
    fresh.occurrence,
    fresh.plan.unwrap(),
    call_scope_snapshot(fresh).unwrap(),
    "sha256:" + "a".repeat(64),
    () => current.val,
  ).unwrap()
  let calls = Ref(0)
  fn restore(read, consumer) {
    start_original_restored_composed(
      fresh.occurrence,
      fresh.plan.unwrap(),
      prefix,
      original_funded_start_provider(calls),
      binding,
      descriptor,
      rows,
      () => current.val,
      saved,
      fresh.limits,
      bound.compiled,
      bound.definition,
      consumer,
      7L,
      5L,
      4194304L,
      4194304L,
      input_body_read=Some(read),
    )
  }
  let (small_ledger, small_read, small_consumer) = original_129_restore_read(
    fresh, 4096L,
  )
  assert_true(restore(small_read, small_consumer) is Err(_))
  assert_eq(calls.val, 0)
  original_composed_test_release(small_ledger, small_consumer)
  let (ledger, _, consumer) = original_129_restore_read(fresh, 67108864L)
  let (foreign_ledger, foreign_read, foreign_consumer) = original_129_restore_read(
    fresh, 67108864L,
  )
  assert_true(restore(foreign_read, consumer) is Err(_))
  assert_eq(calls.val, 0)
  original_composed_test_release(ledger, consumer)
  original_composed_test_release(foreign_ledger, foreign_consumer)
  let (ledger, read, consumer) = original_129_restore_read(fresh, 67108864L)
  current.val = false
  let before = @resources.ledger_usage(ledger)
  assert_true(restore(read, consumer) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), before)
  current.val = true
  let active = restore(read, consumer).unwrap()
  assert_eq(
    @relation.completed_row_count(
      @input.client_infer_completed_input(active.input).unwrap(),
    ),
    129,
  )
  let before_mask = @resources.ledger_usage(ledger).reserved_retention_bytes
  assert_eq(prepare_original_restored_send_mask(active).unwrap(), 129)
  assert_true(
    @resources.ledger_usage(ledger).reserved_retention_bytes > before_mask,
  )
  restrict_model_send_slots(active, Array::make(129, false)).unwrap()
  bind_dispatch_admission(active, fresh.dispatch_admission.unwrap()).unwrap()
  let mut ready = false
  for _ in 0..<200000 {
    if prepared_call_set(active) is Some(prepared) {
      assert_eq(@model.prepared_model_call_count(prepared), Some(129))
      ready = true
      break
    }
    assert_true(advance(active, 1).unwrap() is Continue(..))
  }
  assert_true(ready)
  assert_eq(calls.val, 0)
  assert_true(cancel(active))
  assert_true(original_129_finish(active) is Stopped(..))
  assert_true(cleanup(active).unwrap())
  // The original Read still pays for receiving/export aliases after Model
  // cleanup; only its enclosing actual retirement returns that prefix.
  assert_true(@resources.ledger_usage(ledger).reserved_retention_bytes > 10L)
  original_composed_test_release(ledger, consumer)
  assert_true(cancel(fresh))
  assert_true(original_129_finish(fresh) is Stopped(..))
  assert_true(cleanup(fresh).unwrap())
  original_composed_test_release(fresh_ledger, fresh_consumer)
  assert_eq(fresh_calls.val, 0)
  assert_eq(calls.val, 0)
}

///|
test "materialization witness refuses Ref0 tinyRead foreign completion and unquoted binding" {
  let (fresh, fresh_ledger, fresh_consumer, calls) = original_129_snapshot_fixture()
  let input = @model.prepared_model_input(prepared_call_set(fresh).unwrap()).unwrap()
  let scope = fresh.call_scope.unwrap()
  let identity = fresh.identity.unwrap()
  let rows = fresh.rows.unwrap()
  let bound = fresh.run_binding.unwrap()
  let plan = fresh.plan.unwrap()
  let handed_off = @resources.ledger_usage(fresh_ledger)
  assert_true(
    @input.prepare_original_client_infer_input_materialization(
      (
        fresh.identity_body.unwrap().read,
        fresh_consumer,
        bound.compiled,
        bound.definition,
        plan,
        Ref((0L, 0L)),
      ),
      fresh.occurrence,
      scope,
      input,
      rows,
      identity,
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(fresh_ledger), handed_off)
  let (tiny, tiny_read, tiny_consumer) = original_129_restore_read(fresh, 4096L)
  @publication_host.enter_client_model_read_consumer(
    tiny_consumer,
    bound.compiled,
    bound.definition,
    plan,
    7L,
    5L,
  ).unwrap()
  let forged = Ref((0L, 0L))
  assert_true(
    @input.prepare_original_client_infer_input_materialization(
      (tiny_read, tiny_consumer, bound.compiled, bound.definition, plan, forged),
      fresh.occurrence,
      scope,
      input,
      rows,
      identity,
    )
    is Err(@input.CustodyUnavailable),
  )
  // Fixed facts controls were admitted before the variable-body grow failed.
  // The same Read must preserve that actual prefix until its real retirement;
  // a failed later constructor cannot reset either the Ref or the reservation.
  let control = @relation.retained_readmission_facts_control_bytes()
  assert_eq(forged.val, (7L + control, 5L + control))
  let failed = @resources.ledger_usage(tiny)
  assert_eq(failed.reserved_retention_bytes, 3L + forged.val.0)
  assert_eq(failed.reserved_execution_bytes, 2L + forged.val.1)
  original_composed_test_release(tiny, tiny_consumer)
  assert_eq(@resources.ledger_usage(tiny).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(tiny).reserved_execution_bytes, 0L)
  let (ledger, read, consumer) = original_129_restore_read(fresh, 67108864L)
  @publication_host.enter_client_model_read_consumer(
    consumer,
    bound.compiled,
    bound.definition,
    plan,
    7L,
    5L,
  ).unwrap()
  @publication_host.grow_client_model_read_preparation_consumer_capacity(
    read,
    consumer,
    bound.compiled,
    bound.definition,
    plan,
    3000000L,
    3000000L,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let forged = Ref((0L, 0L))
  let witness = @input.prepare_original_client_infer_input_materialization(
    (read, consumer, bound.compiled, bound.definition, plan, forged),
    fresh.occurrence,
    scope,
    input,
    rows,
    identity,
  ).unwrap()
  assert_true(forged.val.0 > 3000000L)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    forged.val.0 + 3L,
  )
  assert_true(
    @resources.ledger_usage(ledger).reserved_retention_bytes >
    before.reserved_retention_bytes,
  )
  let foreign_prepared = fixture_prepared()
  let (foreign_input, _, _) = original_input_capacity_fixture(
    foreign_prepared,
    call_identity_plan(foreign_prepared),
  )
  let foreign = @input.client_infer_completed_input(foreign_input).unwrap()
  let charged = @resources.ledger_usage(ledger)
  assert_true(
    @input.export_original_client_infer_retained_input(foreign, "", witness)
    is Err(@input.BindingMismatch),
  )
  assert_eq(@resources.ledger_usage(ledger), charged)
  assert_true(@input.cleanup_client_infer_input(foreign_input).unwrap())
  let witness = @input.prepare_original_client_infer_input_materialization(
    (read, consumer, bound.compiled, bound.definition, plan, Ref((0L, 0L))),
    fresh.occurrence,
    scope,
    input,
    rows,
    identity,
  ).unwrap()
  let (_, capacity) = @publication_host.handoff_client_model_read_consumer_input_capacity(
    consumer,
    bound.compiled,
    bound.definition,
    plan,
    scope,
    rows,
    7L,
    5L,
  ).unwrap()
  assert_true(
    @input.export_original_client_infer_retained_input(
      input,
      "x".repeat(20000),
      witness,
    )
    is Err(@input.BindingMismatch),
  )
  assert_true(
    @input.export_original_client_infer_retained_input(input, "", witness)
    is Err(@input.CustodyUnavailable),
  )
  @resources.settle_capacity(ledger, capacity).unwrap()
  original_composed_test_release(ledger, consumer)
  assert_true(cancel(fresh))
  assert_true(original_129_finish(fresh) is Stopped(..))
  assert_true(cleanup(fresh).unwrap())
  original_composed_test_release(fresh_ledger, fresh_consumer)
  assert_eq(calls.val, 0)
}
