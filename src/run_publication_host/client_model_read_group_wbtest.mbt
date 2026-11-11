///|
fn client_model_read_group_fixture() -> (
  ClientCompiledRun,
  @publication.PublicationContract,
  Array[ClientInferPlanGraph],
  @resources.Ledger,
  @resources.OriginalLedgerIdentity,
) raise {
  let prepared = client_two_independent_infer_test_program()
  let bounds = run_materials_limits()
  let plans = prepared_client_composed_infer_occurrences(prepared)
    .unwrap()
    .map(occurrence => {
      issue_installed_client_composed_infer_plan_graph(
        occurrence,
        client_infer_graph_test_execution(prepared, occurrence=Some(occurrence)),
        bounds.sequence,
        bounds.max_evidence_bytes,
        bounds.max_evidence_nodes,
        bounds.max_evidence_depth,
      ).unwrap()
    })
  let compilation = issue_prepared_client_multi_infer_compilation(
    prepared,
    plans,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    compiled, "two-original-models", "same-original", "2026-11-04T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  // Actual Core controls and native compiler. These finite component amounts
  // are not physical-provider or ordinary installed construction evidence.
  let ledger = @resources.create_ledger({
    planning_work: 10,
    attempts: 4,
    holdings: 3,
    transfer_bytes: 100L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 8, 3, 0,
  ).unwrap()
  (compiled, definition, plans, ledger, identity)
}

///|
test "complete compiler Model scopes use one original read in either child start order and retire children before parent" {
  let (compiled, definition, plans, ledger, identity) = client_model_read_group_fixture()
  let scopes = bind_client_model_read_scopes(
    compiled,
    definition,
    plans,
    ledger,
    identity,
    [7L, 9L],
    [5L, 6L],
  ).unwrap()
  let original_scopes = scopes.copy()
  assert_true(physical_equal(scopes[0].identity, scopes[1].identity))
  // Scheduler order is independent of the fixed compiler/declaration order.
  let second = prepare_client_model_read(scopes[1], 9L, 6L).unwrap()
  let second_consumer = claim_client_model_read_preparation(
    second,
    compiled,
    definition,
    plans[1],
    9L,
    6L,
  ).unwrap()
  enter_client_model_read_consumer(
    second_consumer,
    compiled,
    definition,
    plans[1],
    9L,
    6L,
  ).unwrap()
  @resources.charge_planning(ledger, 1).unwrap()
  let first = prepare_client_model_read(scopes[0], 7L, 5L).unwrap()
  assert_true(physical_equal(first.claim, second.claim))
  assert_true(
    claim_client_model_read_preparation(
      first,
      compiled,
      definition,
      plans[1],
      7L,
      5L,
    )
    is Err(ForeignRun),
  )
  let first_consumer = claim_client_model_read_preparation(
    first,
    compiled,
    definition,
    plans[0],
    7L,
    5L,
  ).unwrap()
  assert_true(
    claim_client_model_read_preparation(
      first,
      compiled,
      definition,
      plans[0],
      7L,
      5L,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  enter_client_model_read_consumer(
    first_consumer,
    compiled,
    definition,
    plans[0],
    7L,
    5L,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 19L)
  stop_client_model_read(first).unwrap()
  settle_client_model_read(first, true).unwrap()
  assert_false(
    finish_client_model_read_scope(
      scopes[0],
      compiled,
      definition,
      plans[0],
      true,
    ).unwrap(),
  )
  assert_true(
    settle_client_model_read(second, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 19L)
  settle_client_model_read(second, true).unwrap()
  assert_true(
    finish_client_model_read_scope(
      scopes[1],
      compiled,
      definition,
      plans[1],
      true,
    ).unwrap(),
  )
  assert_true(
    finish_client_model_read_scope(
      original_scopes[0],
      compiled,
      definition,
      plans[0],
      true,
    ).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).planning_work, 1)
}

///|
test "complete compiler Model scope binding refuses foreign duplicated and reordered plans before one shot and cleans an unused child" {
  let (compiled, definition, plans, ledger, identity) = client_model_read_group_fixture()
  let (_, _, foreign) = client_model_read_test_run("foreign-group")
  let before = @resources.ledger_usage(ledger)
  for
    selected in [
      [plans[1], plans[0]],
      [plans[0], plans[0]],
      [plans[0], foreign],
    ] {
    assert_true(
      bind_client_model_read_scopes(
        compiled,
        definition,
        selected,
        ledger,
        identity,
        [7L, 9L],
        [5L, 6L],
      )
      is Err(ForeignRun),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
  }
  let scopes = bind_client_model_read_scopes(
    compiled,
    definition,
    plans,
    ledger,
    identity,
    [7L, 9L],
    [5L, 6L],
  ).unwrap()
  assert_true(
    bind_client_model_read_scopes(
      compiled,
      definition,
      plans,
      ledger,
      identity,
      [7L, 9L],
      [5L, 6L],
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  let first = prepare_client_model_read(scopes[0], 7L, 5L).unwrap()
  assert_true(
    prepare_client_model_read(scopes[0], 7L, 5L)
    is Err(Resource(@resources.SpentClaim)),
  )
  assert_false(
    finish_client_model_read_scope(
      scopes[0],
      compiled,
      definition,
      plans[0],
      true,
    ).unwrap(),
  )
  assert_false(
    finish_client_model_read_scope(
      scopes[1],
      compiled,
      definition,
      plans[1],
      true,
    ).unwrap(),
  )
  settle_client_model_read(first, true).unwrap()
  assert_true(
    finish_client_model_read_scope(
      scopes[0],
      compiled,
      definition,
      plans[0],
      true,
    ).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "closed Model group refuses a competing singular state writer before descriptor and keeps original failed preparation cleanup" {
  let (compiled, definition, plans, ledger, identity) = client_model_read_group_fixture()
  let scopes = bind_client_model_read_scopes(
    compiled,
    definition,
    plans,
    ledger,
    identity,
    [7L, 9L],
    [5L, 6L],
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let writer = @encode.writer(1024, 128, 16)
  assert_true(
    prepare_client_model_read_state(scopes[0], writer, 7L, 5L)
    is Err(@resources.Original(@resources.SpentClaim)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @encode.cancel_writer(writer)
  // A real existing census fence refuses first read entry. The same group
  // keeps that failed attempt and can only retire, never mint a new snapshot.
  assert_false(
    @resources.finish_original_ledger_inventory(ledger, false).unwrap(),
  )
  assert_true(prepare_client_model_read(scopes[0], 7L, 5L) is Err(Resource(_)))
  assert_false(
    finish_client_model_read_scope(
      scopes[0],
      compiled,
      definition,
      plans[0],
      true,
    ).unwrap(),
  )
  assert_true(
    finish_client_model_read_scope(
      scopes[1],
      compiled,
      definition,
      plans[1],
      true,
    ).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
