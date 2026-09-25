///|
/// Native DuckDB tests may skip in an ordinary `moon test`, but a dedicated
/// runner that sets ACTQL_REQUIRE_NATIVE_DUCKDB_TESTS=1 must supply every
/// prerequisite: a missing one is a failure there, never a silent skip.
fn native_duckdb_test_variable(name : String) -> String? {
  match @env.get_env_var(name) {
    Some(value) if value != "" => Some(value)
    _ =>
      if @env.get_env_var("ACTQL_REQUIRE_NATIVE_DUCKDB_TESTS") == Some("1") {
        abort("required native DuckDB test prerequisite missing: " + name)
      } else {
        None
      }
  }
}

///|
fn native_duckdb_test_library() -> String? {
  native_duckdb_test_variable("ACTQL_TEST_DUCKDB_LIBRARY")
}

///|
fn native_resident_test_prerequisites() -> (String, String)? {
  guard native_duckdb_test_library() is Some(library) &&
    native_duckdb_test_variable("ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT")
    is Some(retained_root) else {
    return None
  }
  Some((library, retained_root))
}

///|
fn native_resident_wire() -> @execution.RowWireLimits {
  {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 32,
  }
}

///|
/// The ordinary native standard Host with the resident DuckDB profile
/// installed as a strategy candidate. Local is feasible but estimated slower,
/// so the portable strategy, not this fixture, chooses residency.
fn prepare_native_resident_run(
  library_path : String,
  retained_root : String,
  max_file_bytes? : Int64 = 100000L,
  import_limits? : @native_host.NativeComputeImportLimits = native_compute_import_limits(),
  import_scratch_bytes? : Int64 = 2000000L,
  task_execution_bytes? : Int64 = 134217728L,
) -> (
  @strategy.CapturedDAG,
  @native_host.NativeStandardStrategyRun,
  @mock.MockQueryIssuer,
) raise {
  // One import plus three task transfers fit the Run's transfer ceiling.
  let (run, issuer) = captured_graph_fixture(
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 1000000L,
      retained_bytes: 32000000L,
      execution_bytes: 134217728L,
    }),
  )
  let registry = search_registry()
  let host = @dbhost.configure_strategy_dispatch(
    run,
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    @connector.capability_registration_at(registry, 1).unwrap(),
    dispatch_test_generated(run),
    dispatch_test_limits(),
  ).unwrap()
  @dbhost.configure_dispatch_retained_output(host, max_file_bytes, Some(1L)).unwrap()
  let count = @strategy.graph_task_count(@strategy.captured_dag_graph(run)) - 1
  let profiles = Array::makei(count, _ => @dbhost.DispatchEstimateProfile::{
    local_rates: [
      {
        work_slots: [0, 1, 2, 3, 4],
        fixed_ms: Some(1000L),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_rates: [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
        fixed_ms: Some(100L),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_capacity: {
      transfer_bytes: 100000L,
      retained_bytes: 4000000L,
      execution_bytes: task_execution_bytes,
    },
    output_rows_per_mille: Some(1000),
  })
  @dbhost.configure_dispatch_estimates(host, profiles, {
    max_offers: count * 3,
    max_strategies: 27,
    max_work: 10000,
    max_revisions: count + 1,
  }).unwrap()
  let shared = fn(ms : Int64) {
    @strategy.prepare_shared_work(
      run,
      1,
      [{ work_slots: [0], milliseconds: Some(ms), }],
      3,
    ).unwrap()
  }
  let profile = @strategy.prepare_resident_profile(
    run,
    @connector.prepare_resource_binding(
      registry,
      @connector.capability_registration_at(registry, 1).unwrap(),
    ).unwrap(),
    67108864L,
    shared(1L),
    shared(1L),
    Array::make(count + 1, @strategy.ResidentImportEstimate::{
      work: shared(1L),
      transfer_bytes: 100000L,
      scratch_bytes: import_scratch_bytes,
      table_bytes: 4000000L,
    }),
  ).unwrap()
  @dbhost.configure_resident_dispatch(
    host,
    profile,
    Array::make(count, [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
        fixed_ms: Some(1L),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ]),
  ).unwrap()
  let library = @native_duckdb.load_library(library_path).unwrap()
  let owner = @native_host.open_native_standard_strategy_run(
    host,
    import_limits,
    100000L,
    // The environment's engine budget: exactly the selected profile bytes.
    67108864L,
    library=Some(library),
    retained_profile={
      root_path: retained_root,
      run_occurrence: "native-resident-" + @env.now().to_string(),
      max_file_bytes,
      wire: native_resident_wire(),
      max_batch_bytes: 4096,
      max_chunk_rows: 100,
    },
  ).unwrap()
  (run, owner, issuer)
}

///|
fn native_resident_task_cid(
  owner : @native_host.NativeStandardStrategyRun,
  task : Int,
) -> String {
  let output = @native_host.read_native_standard_task_output(
    owner,
    task,
    100,
    { max_nodes: 10000, max_text_bytes: 10000, max_depth: 32, max_work: 10000, },
    native_resident_wire(),
    4096,
  ).unwrap()
  @execution.row_wire_cid(
    @execution.identify_completed_rows(output, native_resident_wire()).unwrap(),
  )
}

///|
fn assert_native_resident_ledger_released(
  run : @strategy.CapturedDAG,
) -> Unit raise {
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.uncertain_transfer_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
}

///|
test "native resident Host shares one database and imports each producer once" {
  guard native_resident_test_prerequisites() is Some((library, retained_root)) else {
    return
  }
  let (captured, owner, issuer) = prepare_native_resident_run(
    library, retained_root,
  )
  // Graph: source(0) -> task 1, source(0) -> task 2, task 1 -> task 3.
  // [imports, borrowed inputs, committed resident tables after the task]
  // Task 1 imports the source once and leaves it for its second consumer.
  // Task 2 borrows it without import and retires it as its last use. Task 3
  // borrows task 1's committed output, retiring it and task 2's unconsumed
  // table, so only its own output remains.
  let expected = [(1, 0, 2), (1, 1, 2), (1, 2, 1)]
  let ledger = @strategy.captured_dag_ledger(captured)
  for index, (imports, borrowed, tables) in expected {
    let completion = @native_host.execute_next_native_standard_strategy_task(
        owner,
      )
      .unwrap()
      .unwrap()
    assert_eq(completion.task, index + 1)
    // Completion is published only with its sealed independent holding, and
    // the holding identifies exactly the completed rows.
    let holding = completion.holding.unwrap()
    assert_eq(holding.rows, @execution.completed_row_count(completion.output))
    assert_eq(holding.rows_cid, native_resident_task_cid(owner, index + 1))
    let observed = @native_host.native_standard_strategy_run_resident_observation(
      owner,
    )
    assert_eq(observed.environments, 1)
    assert_eq(observed.imports, imports)
    assert_eq(observed.borrowed_inputs, borrowed)
    // Receiver views were connection-local to the finished task transaction.
    assert_eq(observed.temporary_views, 0L)
    assert_eq(observed.tables, tables.to_int64())
    // Task completion does not end the database: its engine budget stays
    // reserved in the common ledger until the Run's final release.
    assert_true(
      @resources.ledger_usage(ledger).reserved_execution_bytes >= 67108864L,
    )
  }
  assert_true(
    @native_host.execute_next_native_standard_strategy_task(owner) is Ok(None),
  )
  let resident_cids = [1, 2, 3].map(task => {
    native_resident_task_cid(owner, task)
  })
  assert_true(@native_host.close_native_standard_strategy_run(owner).unwrap())
  assert_native_resident_ledger_released(captured)
  @mock.close_mock_query_issuer(issuer)
  // The same Program through the per-task fresh-database path.
  let (fresh_run, fresh, fresh_issuer) = prepare_native_publication_duckdb_run(
    library,
    retained_root~,
  )
  @native_host.execute_native_standard_strategy_run(fresh).unwrap()
  assert_eq(
    @native_host.native_standard_strategy_run_resident_observation(fresh).environments,
    0,
  )
  for task in [1, 2, 3] {
    assert_eq(native_resident_task_cid(fresh, task), resident_cids[task - 1])
  }
  assert_true(@native_host.close_native_standard_strategy_run(fresh).unwrap())
  assert_native_resident_ledger_released(fresh_run)
  @mock.close_mock_query_issuer(fresh_issuer)
}

///|
test "native resident task failure keeps the environment owner until release" {
  guard native_resident_test_prerequisites() is Some((library, retained_root)) else {
    return
  }
  // The committed source table exists; the task's holding cannot be sealed.
  let (captured, owner, issuer) = prepare_native_resident_run(
    library,
    retained_root,
    max_file_bytes=1L,
  )
  assert_true(
    @native_host.execute_next_native_standard_strategy_task(owner)
    is Err(DuckDB(_)),
  )
  assert_false(@strategy.captured_task_completed(captured, 1))
  let observed = @native_host.native_standard_strategy_run_resident_observation(
    owner,
  )
  assert_eq(observed.imports, 1)
  // The failed task's views, result table and retirements rolled back.
  assert_eq(observed.temporary_views, 0L)
  assert_eq(observed.tables, 1L)
  // The environment reservation and the failed task's owner remain.
  assert_true(
    @resources.ledger_usage(@strategy.captured_dag_ledger(captured)).reserved_execution_bytes >=
    67108864L,
  )
  assert_eq(@native_host.native_standard_strategy_run_task_count(owner), 1)
  assert_true(
    @native_host.execute_next_native_standard_strategy_task(owner)
    is Err(Closed),
  )
  assert_true(@native_host.close_native_standard_strategy_run(owner).unwrap())
  // Cleanup is idempotent once confirmed.
  assert_true(@native_host.close_native_standard_strategy_run(owner).unwrap())
  assert_native_resident_ledger_released(captured)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "native resident import rejection returns its table and environment" {
  guard native_resident_test_prerequisites() is Some((library, retained_root)) else {
    return
  }
  let (captured, owner, issuer) = prepare_native_resident_run(
    library,
    retained_root,
    import_limits={ ..native_compute_import_limits(), max_rows: 1, },
  )
  assert_true(
    @native_host.execute_next_native_standard_strategy_task(owner)
    is Err(DuckDB(Start(Physical(ImportRows)))),
  )
  let observed = @native_host.native_standard_strategy_run_resident_observation(
    owner,
  )
  assert_eq(observed.environments, 1)
  assert_eq(observed.imports, 0)
  assert_eq(observed.tables, 0L)
  assert_eq(@native_host.native_standard_strategy_run_task_count(owner), 0)
  assert_true(@native_host.close_native_standard_strategy_run(owner).unwrap())
  assert_native_resident_ledger_released(captured)
  @mock.close_mock_query_issuer(issuer)
}

///|
/// Run task 1 once with ample ceilings and return the native import allowance
/// and the task's whole execution demand that the Host computed for it.
fn observe_native_resident_ceilings(
  library : String,
  retained_root : String,
) -> (Int64, Int64) raise {
  let (captured, owner, issuer) = prepare_native_resident_run(
    library, retained_root,
  )
  ignore(
    @native_host.execute_next_native_standard_strategy_task(owner)
    .unwrap()
    .unwrap(),
  )
  let observed = @native_host.native_standard_strategy_run_resident_observation(
    owner,
  )
  assert_true(@native_host.close_native_standard_strategy_run(owner).unwrap())
  assert_native_resident_ledger_released(captured)
  @mock.close_mock_query_issuer(issuer)
  assert_true(observed.import_scratch_bytes > 0L)
  assert_true(observed.task_demand_bytes > 67108864L)
  (observed.import_scratch_bytes, observed.task_demand_bytes)
}

///|
/// A resident ceiling one unit short must reject before its covered
/// allocation: no table, import, transaction or task owner exists, and
/// release leaves nothing in the ledger.
fn assert_native_resident_rejected_before_work(
  captured : @strategy.CapturedDAG,
  owner : @native_host.NativeStandardStrategyRun,
  issuer : @mock.MockQueryIssuer,
) -> Unit raise {
  assert_true(
    @native_host.execute_next_native_standard_strategy_task(owner)
    is Err(DuckDB(Start(Strategy(Physical(InvalidCharge))))),
  )
  let observed = @native_host.native_standard_strategy_run_resident_observation(
    owner,
  )
  assert_eq(observed.imports, 0)
  assert_eq(observed.tables, 0L)
  assert_eq(observed.temporary_views, 0L)
  assert_eq(@native_host.native_standard_strategy_run_task_count(owner), 0)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(captured))
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.transferred_bytes, 0L)
  // Only the provisioned environment itself remains until final release.
  assert_eq(usage.reserved_execution_bytes, 67108864L)
  assert_true(@native_host.close_native_standard_strategy_run(owner).unwrap())
  assert_native_resident_ledger_released(captured)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "native resident import allowance is admitted exactly before any import" {
  guard native_resident_test_prerequisites() is Some((library, retained_root)) else {
    return
  }
  let (import_scratch, _) = observe_native_resident_ceilings(
    library, retained_root,
  )
  // Exactly enough: the import is admitted and completes.
  let (captured, owner, issuer) = prepare_native_resident_run(
    library,
    retained_root,
    import_scratch_bytes=import_scratch,
  )
  ignore(
    @native_host.execute_next_native_standard_strategy_task(owner)
    .unwrap()
    .unwrap(),
  )
  assert_eq(
    @native_host.native_standard_strategy_run_resident_observation(owner).imports,
    1,
  )
  assert_true(@native_host.close_native_standard_strategy_run(owner).unwrap())
  assert_native_resident_ledger_released(captured)
  @mock.close_mock_query_issuer(issuer)
  // One byte short: rejected before any statement is compiled.
  let (captured, owner, issuer) = prepare_native_resident_run(
    library,
    retained_root,
    import_scratch_bytes=import_scratch - 1L,
  )
  assert_native_resident_rejected_before_work(captured, owner, issuer)
}

///|
test "native resident task demand is admitted exactly before any import" {
  guard native_resident_test_prerequisites() is Some((library, retained_root)) else {
    return
  }
  let (_, demand) = observe_native_resident_ceilings(library, retained_root)
  let (captured, owner, issuer) = prepare_native_resident_run(
    library,
    retained_root,
    task_execution_bytes=demand,
  )
  ignore(
    @native_host.execute_next_native_standard_strategy_task(owner)
    .unwrap()
    .unwrap(),
  )
  assert_true(@native_host.close_native_standard_strategy_run(owner).unwrap())
  assert_native_resident_ledger_released(captured)
  @mock.close_mock_query_issuer(issuer)
  let (captured, owner, issuer) = prepare_native_resident_run(
    library,
    retained_root,
    task_execution_bytes=demand - 1L,
  )
  assert_native_resident_rejected_before_work(captured, owner, issuer)
}

///|
test "native resident unconfirmed rollback keeps its owner and is never reused" {
  guard native_resident_test_prerequisites() is Some((library, retained_root)) else {
    return
  }
  // A real task failure (the holding cannot be sealed) whose rollback end is
  // then withheld by the whitebox seam.
  let (captured, owner, issuer) = prepare_native_resident_run(
    library,
    retained_root,
    max_file_bytes=1L,
  )
  @native_host.fail_next_native_resident_transaction_end(owner, false)
  guard @native_host.execute_next_native_standard_strategy_task(owner)
    is Err(DuckDB(Execution(failure))) else {
    fail("resident failure was not reported as an execution failure")
  }
  // Both the original failure and the rollback failure are preserved.
  assert_true(failure.primary is Physical(RetainedFile(_)))
  assert_true(failure.rollback is Some(_))
  assert_false(@strategy.captured_task_completed(captured, 1))
  let observed = @native_host.native_standard_strategy_run_resident_observation(
    owner,
  )
  assert_eq(observed.unconfirmed_environments, 1)
  assert_eq(observed.imports, 1)
  // The task's own reservation remains beside the environment's.
  let ledger = @strategy.captured_dag_ledger(captured)
  assert_true(
    @resources.ledger_usage(ledger).reserved_execution_bytes > 67108864L,
  )
  assert_true(
    @native_host.execute_next_native_standard_strategy_task(owner)
    is Err(Closed),
  )
  // Destroying the database confirms the stop; retries never re-execute.
  assert_true(@native_host.close_native_standard_strategy_run(owner).unwrap())
  assert_true(@native_host.close_native_standard_strategy_run(owner).unwrap())
  assert_eq(@native_host.native_standard_strategy_run_task_count(owner), 1)
  assert_false(@strategy.captured_task_completed(captured, 1))
  assert_native_resident_ledger_released(captured)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "native resident unconfirmed commit keeps completed work and blocks reuse" {
  guard native_resident_test_prerequisites() is Some((library, retained_root)) else {
    return
  }
  let (captured, owner, issuer) = prepare_native_resident_run(
    library, retained_root,
  )
  let first = @native_host.execute_next_native_standard_strategy_task(owner)
    .unwrap()
    .unwrap()
  assert_eq(first.task, 1)
  @native_host.fail_next_native_resident_transaction_end(owner, true)
  guard @native_host.execute_next_native_standard_strategy_task(owner)
    is Err(DuckDB(Execution(failure))) else {
    fail("injected commit failure was not reported")
  }
  assert_true(failure.primary is Physical(Runtime(_)))
  assert_true(failure.rollback is Some(_))
  assert_true(@strategy.captured_task_completed(captured, 1))
  assert_false(@strategy.captured_task_completed(captured, 2))
  let observed = @native_host.native_standard_strategy_run_resident_observation(
    owner,
  )
  assert_eq(observed.unconfirmed_environments, 1)
  assert_eq(observed.imports, 1)
  assert_true(
    @native_host.execute_next_native_standard_strategy_task(owner)
    is Err(Closed),
  )
  assert_true(@native_host.close_native_standard_strategy_run(owner).unwrap())
  assert_eq(@native_host.native_standard_strategy_run_task_count(owner), 2)
  assert_native_resident_ledger_released(captured)
  @mock.close_mock_query_issuer(issuer)
}
