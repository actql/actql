///|
fn client_model_read_test_run(
  run_id : String,
) -> (ClientCompiledRun, @publication.PublicationContract, ClientInferPlanGraph) {
  let prepared = client_infer_prefix_test_program()
  let plan = client_infer_material_test_graph(prepared)
  let compilation = issue_prepared_client_infer_compilation(
    prepared,
    plan,
    run_materials_manifests(),
    1000,
    1000,
    100000,
    10000,
    100,
  ).unwrap()
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    compiled, "read-scope", run_id, "2026-10-12T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (compiled, definition, plan)
}

///|
test "checked original model read binds Run Host and same ledger before handoff" {
  let (compiled, definition, plan) = client_model_read_test_run("original")
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "foreign",
  )
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 10L,
    execution_bytes: 7L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  // The compiler can issue several admitted Runs for the same Program. The
  // chosen original Definition is bound at preparation, not inferred from the
  // Program identity. A later equal-Program/other-Run handoff must be refused.
  assert_true(
    begin_client_model_read_scope(
      compiled, definition, foreign_plan, ledger, bootstrap, 1, 0, 0,
    )
    is Err(ForeignRun),
  )
  let scope = begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 1, 0, 0,
  ).unwrap()
  let prepared = prepare_client_model_read(scope, 7L, 5L).unwrap()
  assert_true(client_model_read_available(prepared, compiled, definition, plan))
  assert_true(
    !client_model_read_available(prepared, compiled, foreign_definition, plan),
  )
  assert_true(
    handoff_client_model_read(prepared, compiled, foreign_definition, plan)
    is Err(ForeignRun),
  )
  assert_true(
    !client_model_read_available(
      prepared, foreign, foreign_definition, foreign_plan,
    ),
  )
  assert_true(
    handoff_client_model_read(
      prepared, foreign, foreign_definition, foreign_plan,
    )
    is Err(ForeignRun),
  )
  assert_true(
    physical_equal(
      handoff_client_model_read(prepared, compiled, definition, plan).unwrap(),
      ledger,
    ),
  )
  assert_true(
    !client_model_read_available(prepared, compiled, definition, plan),
  )
  assert_true(
    settle_client_model_read(prepared, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  settle_client_model_read(prepared, true).unwrap()
  assert_true(
    settle_client_model_read(prepared, true)
    is Err(Resource(@resources.SpentClaim)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 3L)
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
}

///|
test "checked original model read rejects unfunded bootstrap before Run binding" {
  let (compiled, definition, plan) = client_model_read_test_run("original")
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 10L,
    execution_bytes: 7L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 0L, 0L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    begin_client_model_read_scope(
      compiled, definition, plan, ledger, bootstrap, 1, 0, 0,
    )
    is Err(InvalidBootstrap),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @resources.settle_capacity(ledger, bootstrap).unwrap()
}

///|
test "checked original model read capacity handoff binds Run and preserves cleanup custody" {
  let (compiled, definition, plan) = client_model_read_test_run("original")
  let (_, foreign_definition, _) = client_model_read_test_run("foreign")
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 20L,
    execution_bytes: 12L,
  }).unwrap()
  let amounts : @resources.QuantityAmounts = {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }
  @resources.configure_quantities(ledger, amounts).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 2, 0, 0,
  ).unwrap()
  let read = prepare_client_model_read(scope, 7L, 5L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let quantities = @resources.quantity_usage(ledger)
  // Exact fixture charges are not an adopted physical layout. This caller
  // guards before allocating its additional control; no second token is made.
  assert_true(
    client_model_read_preparation_available(
      read,
      compiled,
      definition,
      plan,
      5L,
      retained_bytes=7L,
    ),
  )
  assert_false(
    client_model_read_preparation_available(
      read,
      compiled,
      definition,
      plan,
      5L,
      retained_bytes=8L,
    ),
  )
  assert_false(
    client_model_read_preparation_available(
      read,
      compiled,
      definition,
      plan,
      5L,
      retained_bytes=-1L,
    ),
  )
  assert_false(
    client_model_read_preparation_available(
      read,
      compiled,
      foreign_definition,
      plan,
      5L,
      retained_bytes=7L,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  assert_true(
    client_model_read_preparation_available(
      read, compiled, definition, plan, 5L,
    ),
  )
  assert_false(
    client_model_read_preparation_available(
      read, compiled, definition, plan, 6L,
    ),
  )
  assert_false(
    client_model_read_preparation_available(
      read, compiled, foreign_definition, plan, 5L,
    ),
  )
  assert_true(
    handoff_client_model_read_capacity(
      read, compiled, foreign_definition, plan, 10L, 5L,
    )
    is Err(ForeignRun),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    handoff_client_model_read_capacity(
      read, compiled, definition, plan, 10L, 6L,
    )
    is Err(Resource(@resources.Resource(@resources.ExecutionLimit))),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(client_model_read_available(read, compiled, definition, plan))
  let (same, token) = handoff_client_model_read_capacity(
    read, compiled, definition, plan, 10L, 5L,
  ).unwrap()
  assert_true(physical_equal(same, ledger))
  assert_false(
    client_model_read_preparation_available(
      read,
      compiled,
      definition,
      plan,
      5L,
      retained_bytes=7L,
    ),
  )
  assert_true(@resources.capacity_reservation_matches(same, token, 10L, 5L))
  assert_true(@resources.quantity_configuration_matches(same, Some(amounts)))
  assert_eq(@resources.quantity_usage(same), quantities)
  assert_eq(@resources.ledger_usage(same).reserved_retention_bytes, 20L)
  assert_eq(@resources.ledger_usage(same).reserved_execution_bytes, 12L)
  assert_eq(@resources.ledger_usage(same).attempts, 0)
  assert_true(
    handoff_client_model_read_capacity(
      read, compiled, definition, plan, 10L, 5L,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  assert_true(
    settle_client_model_read(read, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(same).reserved_retention_bytes, 20L)
  settle_client_model_read(read, true).unwrap()
  assert_eq(@resources.ledger_usage(same).reserved_retention_bytes, 13L)
  assert_false(@resources.finish_original_ledger_inventory(same, true).unwrap())
  @resources.settle_capacity(same, token).unwrap()
  assert_true(@resources.finish_original_ledger_inventory(same, true).unwrap())
  assert_eq(@resources.ledger_usage(same).reserved_retention_bytes, 0L)
}

///|
test "Model binding after original preparation retains its recorded reservation and refuses rebinding" {
  let (compiled, definition, plan) = client_model_read_test_run("prepared")
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "other",
  )
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 10L, 10L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 2, 0, 0,
  ).unwrap()
  let input = [1]
  let capacity : @resources.PreparationCapacity[Array[Int], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    20L,
    20L,
    max_borrowers=1,
  ).unwrap()
  @resources.complete_preparation_capacity(capacity, input, [2], 15L, 0L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    bind_client_model_read_scope(
      compiled, definition, foreign_plan, ledger, identity,
    )
    is Err(ForeignRun),
  )
  let other_ledger = @resources.create_ledger(@resources.ledger_limits(ledger)).unwrap()
  assert_true(
    bind_client_model_read_scope(
      compiled, definition, plan, other_ledger, identity,
    )
    is Err(Resource(@resources.ForeignOrigin)),
  )
  let scope = bind_client_model_read_scope(
    compiled, definition, plan, ledger, identity,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    bind_client_model_read_scope(compiled, definition, plan, ledger, identity)
    is Err(Resource(@resources.SpentClaim)),
  )
  assert_true(
    bind_client_model_read_scope(
      foreign, foreign_definition, foreign_plan, ledger, identity,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  let read = prepare_client_model_read(scope, 30L, 30L).unwrap()
  assert_true(
    physical_equal(
      handoff_client_model_read(read, compiled, definition, plan).unwrap(),
      ledger,
    ),
  )
  settle_client_model_read(read, true).unwrap()
  // Cleanup cannot return bootstrap while the actual preparation is retained.
  assert_false(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 25L)
  assert_true(@resources.retire_preparation_capacity(capacity).unwrap())
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}
