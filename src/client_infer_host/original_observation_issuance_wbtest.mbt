///|
// Real original Scope/Run/Model with an actual fixture provider and synthetic
// allowances. These are not installed Node profiles, Store ACKs or public E2E.
fn original_observation_test_start(
  producer? : Ref[@resources.Reservation?]? = None,
) -> (Execution, @resources.Ledger, @publication_host.ClientModelReadConsumer) {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let (compiled, _) = original_input_capacity_run(prepared, plan)
  // Select the original Result policy before issuing the checked read origin.
  // Do not replace an already issued Scope/Run with a newly compiled lookalike.
  let policy_wire = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  let compiled = @publication_host.with_client_infer_result_policy(
    compiled,
    invocation_fixture_policy_cid(),
    policy_wire,
    16384,
    1024,
    20,
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "original-observation", "run", "2026-10-12T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let ledger = @resources.create_ledger({
    ..limits.model.ledger,
    attempts: Int::min(limits.model.ledger.attempts, 4),
    transfer_bytes: Int64::min(limits.model.ledger.transfer_bytes, 133072L),
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let original_scope = @publication_host.begin_client_model_read_scope(
    compiled,
    definition,
    plan,
    ledger,
    bootstrap,
    if producer is Some(_) {
      5
    } else {
      4
    },
    if producer is Some(_) {
      3
    } else {
      2
    },
    0,
  ).unwrap()
  if producer is Some(record) {
    record.val = Some(@resources.reserve_attempt(ledger, 1L, 7L, 5L).unwrap())
  }
  let read = @publication_host.prepare_client_model_read(original_scope, 7L, 5L).unwrap()
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
  let configuration = evidence_account(@authorization.Allow)
  let permit = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    configuration,
    "fixture-principal",
    "2026-10-12T00:00:00.000Z",
    observe_current=() => Ok((configuration, "2026-10-12T00:00:00.000Z")),
  ).unwrap()
  bind_dispatch_admission(active, permit).unwrap()
  (active, ledger, consumer)
}

///|
test "original observation issuance retains same completed producer output and pending scratch" {
  let producer : Ref[@resources.Reservation?] = Ref(None)
  let (active, ledger, _) = original_observation_test_start(
    producer=Some(producer),
  )
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let producer = producer.val.unwrap()
  let output = @resources.retain_allocation(ledger, producer, 4L).unwrap()
  @resources.settle_completed_output_reservation(
    ledger,
    producer,
    Some(output),
    4L,
    3L,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@resources.reservation_pending(producer))
  issuance_finish(issued)
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  // Publication retirement is not the independent producer scratch/output ACK.
  assert_true(@resources.reservation_pending(producer))
  @resources.settle_reservation(ledger, producer).unwrap()
  @resources.release_allocation(ledger, output).unwrap()
  assert_true(cleanup(active).unwrap())
}

///|
test "original observation issuance keeps same funding through binding and caller retirement" {
  let (active, ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  // The existing metadata component is 16 * 4096 + 1 * 128. The execution
  // allowance is a synthetic test grant, not a full Node physical profile.
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let quantities = @resources.quantity_usage(ledger)
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(issued.state.count, 1)
  issuance_finish(issued)
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.planning_work, before.planning_work + 3)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  let bound = active.run_binding.unwrap()
  let first = bind_issued_invocation(
    active,
    bound.compiled,
    bound.definition,
    issued,
  ).unwrap()
  let second = bind_issued_invocation(
    active,
    bound.compiled,
    bound.definition,
    issued,
  ).unwrap()
  assert_false(cleanup_observation_issuance(issued).unwrap())
  assert_true(release_invocation_binding(first))
  assert_false(cleanup_observation_issuance(issued).unwrap())
  assert_true(invocation_binding_output(second) is Some(_))
  assert_true(release_invocation_binding(second))
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(issued.state.funding is None)
  assert_true(issued.state.owners.is_empty())
  assert_true(issued.state.captures.is_empty())
  assert_true(issued.state.output_uses.is_empty())
  assert_true(issued.state.slots.is_empty())
  assert_true(observation_issuance_value(issued) is None)
  // Issuer cleanup is not acknowledgement of later Store bodies/alias cleanup.
  assert_eq(@resources.ledger_usage(ledger), after)
  assert_false(cleanup(active).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    after.reserved_retention_bytes - 65664L,
  )
  assert_true(cleanup(active).unwrap())
}

///|
test "original observation issuance refuses one short foreign and released borrows before capture" {
  let (active, ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let short = reserve_original_infer_publication_capacity(active, 65663L, 7L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let uses = active.output_uses
  assert_true(
    start_original_observation_issuance(active, short, issuance_limits())
    is Err(Model(@model.Ledger(@resources.RetentionLimit))),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(active.output_uses, uses)
  assert_true(release_original_infer_publication_capacity(short).unwrap())
  assert_true(
    start_original_observation_issuance(active, short, issuance_limits())
    is Err(Model(@model.OutputIdentity)),
  )
  let (foreign, foreign_ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(foreign) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(
    foreign, 65664L, 7L,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let other_before = @resources.ledger_usage(foreign_ledger)
  assert_true(
    start_original_observation_issuance(active, capacity, issuance_limits())
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.ledger_usage(foreign_ledger), other_before)
  assert_eq(active.output_uses, uses)
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(foreign).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "original observation cancellation after positive work keeps caller capacity" {
  let (active, ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  assert_false(advance_observation_issuance(issued, 1).unwrap().0)
  assert_eq(
    @resources.ledger_usage(ledger).planning_work,
    before.planning_work + 1,
  )
  assert_true(cancel_observation_issuance(issued))
  assert_true(
    advance_observation_issuance(issued, 1) is Err(Model(@model.Cancelled)),
  )
  assert_true(observation_issuance_value(issued) is None)
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_false(cleanup(active).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "original observation handed off read stop refuses new issuance without blocking cleanup" {
  let (active, ledger, consumer) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  @publication_host.stop_client_model_read_consumer(consumer).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    reserve_original_infer_publication_capacity(active, 65664L, 7L)
    is Err(Model(@model.OutputIdentity)),
  )
  assert_true(
    start_original_observation_issuance(active, capacity, issuance_limits())
    is Err(Model(@model.OutputIdentity)),
  )
  assert_true(
    advance_observation_issuance(issued, 1) is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // Stopping is not a new dispatch grant and is not release of this borrow.
  // It also must not require a dispatch Allow to retire already-owned metadata.
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "complete original observation refuses duplicate and foreign parent before metadata mutation" {
  let (active, ledger, _) = original_observation_test_start()
  let (foreign, foreign_ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_true(fixture_finish(foreign) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let foreign_before = @resources.ledger_usage(foreign_ledger)
  for owners in [[], [active, active], [active, foreign]] {
    assert_true(
      start_complete_original_observation_issuance(
        owners,
        capacity,
        issuance_limits(),
      )
      is Err(Model(@model.OutputIdentity)),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_eq(@resources.ledger_usage(foreign_ledger), foreign_before)
  }
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(foreign).unwrap())
}
