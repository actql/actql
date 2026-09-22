///|
fn native_compute_transport_limits() -> @duckdb.TransportColumnLimits {
  {
    max_bytes: 4096,
    max_nodes: 128,
    max_columns: 8,
    max_rows: 2,
    max_text_bytes: 512,
  }
}

///|
fn native_compute_import_limits() -> @native_host.NativeComputeImportLimits {
  {
    max_rows: 10,
    max_cells: 40,
    max_parameters: 8,
    max_sql_bytes: 10000,
    max_batch_rows: 2,
  }
}

///|
fn native_compute_setup(
  input : @execution.ProducerRead,
  transport? : @duckdb.TransportColumnLimits = native_compute_transport_limits(),
) -> @duckdb_driver.ComputeHostConfiguration raise {
  let request = @connector.prepare_fixed_compute_request([input], {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 2,
    max_value_bytes: 5,
    common_fragment: None,
  }).unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "duckdb", acquisition: false, fixed_compute: true, }],
    1,
    6,
  ).unwrap()
  let prepared = @duckdb_compute.duckdb_fixed_compute_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    request,
    "fixed",
    native_compile_limits(),
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(1L), }],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [@connector.prepared_compute_candidate(prepared)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("fixed proposal")
  }
  @duckdb_driver.configure_compute_host(
    choice,
    prepared,
    @execution.generated_completion_preparation(
      query_generated(@execution.producer_read_receiver(input)),
    ),
    fixed_compute_attempt_limits(),
    transport,
  )
}

///|
fn native_compute_strategy_selection(
  run : @strategy.CapturedDAG,
  registry : @connector.CapabilityRegistry,
) -> @strategy.StrategyRevision {
  let retention = @duckdb_compute.duckdb_task_retention_capacity(
    fixed_compute_attempt_limits(),
  ).unwrap()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 1,
  }).unwrap()
  let offers = []
  for task in [1, 2, 3] {
    for registration in 0..<2 {
      let lines : Array[@cost.SerialEstimateLine] = if registration == 0 {
        [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(10L), }]
      } else {
        [
          { work_slots: [0, 2, 3, 5, 6, 7], milliseconds: Some(1L), },
          { work_slots: [1, 4], milliseconds: Some(20L), },
        ]
      }
      offers.push(
        @strategy.prepare_task_offer(
          run,
          task,
          @connector.capability_registration_at(registry, registration).unwrap(),
          if registration == 0 {
            5
          } else {
            8
          },
          lines,
          {
            transfer_bytes: 100000L,
            retained_bytes: retention,
            execution_bytes: 134217728L,
          },
          100,
        ).unwrap(),
      )
    }
  }
  @strategy.revise_strategy(run, offers, registry, None).unwrap() |> ignore
  @strategy.captured_dag_strategy(run).unwrap()
}

///|
test "native fixed Compute rolls back a failed physical transaction" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let input = duckdb_captured_input(filter="id > 2")
  let database = @native_duckdb.load_library(path)
    .unwrap()
    .open_database(@native_duckdb.restricted_open_limits(134217728L))
    .unwrap()
  let runtime = @native_host.start_native_compute_runtime(
    native_compute_setup(input, transport={
      ..native_compute_transport_limits(),
      max_bytes: 1,
    }),
    database,
    native_compute_import_limits(),
  ).unwrap()
  assert_true(
    @native_host.execute_native_compute_runtime(runtime)
    is Err({ rollback: None, .. }),
  )
  assert_true(
    @native_host.execute_native_compute_runtime(runtime)
    is Err({ primary: RuntimeState, rollback: None, }),
  )
  assert_true(database.begin_transaction() is Err(_))
  assert_true(@native_host.native_compute_runtime_output(runtime) is Err(_))
  @native_host.close_native_compute_runtime(runtime)
}

///|
test "native DuckDB executes portable fixed Compute without Node" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let input = duckdb_captured_input(filter="id > 2")
  let database = @native_duckdb.load_library(path)
    .unwrap()
    .open_database(@native_duckdb.restricted_open_limits(134217728L))
    .unwrap()
  let runtime = @native_host.start_native_compute_runtime(
    native_compute_setup(input),
    database,
    native_compute_import_limits(),
  ).unwrap()
  let output = @native_host.execute_native_compute_runtime(runtime).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
  assert_true(
    physical_equal(
      @native_host.native_compute_runtime_output(runtime).unwrap(),
      output,
    ),
  )
  @native_host.close_native_compute_runtime(runtime)
  @native_host.close_native_compute_runtime(runtime)
  assert_true(@native_host.native_compute_runtime_output(runtime) is Err(_))
}

///|
test "native fixed Compute rejects import capacity before execution" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let input = duckdb_captured_input(filter="id > 2")
  let database = @native_duckdb.load_library(path)
    .unwrap()
    .open_database(@native_duckdb.restricted_open_limits(134217728L))
    .unwrap()
  assert_true(
    @native_host.start_native_compute_runtime(
      native_compute_setup(input),
      database,
      { ..native_compute_import_limits(), max_cells: 1, },
    )
    is Err(ImportCells),
  )
  assert_true(database.begin_transaction() is Err(_))
}

///|
test "standard dispatcher completes native fixed Compute without Node" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let (run, issuer) = captured_graph_fixture()
  let registry = search_registry()
  let revision = native_compute_strategy_selection(run, registry)
  let registration = @strategy.strategy_registration(revision, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let generated = dispatch_test_generated(run)
  let limits = duckdb_dispatch_module_limits()
  let implementation = @duckdb_driver.prepare_duckdb_dispatch_module(
    driver,
    registry,
    registration,
    generated.map(@execution.generated_completion_preparation),
    limits,
  ).unwrap()
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(_context : Unit, task, selected, request) {
          @duckdb_driver.prepare_duckdb_dispatch(
            implementation, task, selected, request,
          )
        },
      ),
    ],
    1,
  ).unwrap()
  let host = @host_driver.open_dispatch_host(
    driver,
    entries,
    limits.capacity,
    100,
    10000,
  ).unwrap()
  let task = @host_driver.prepare_next_installed_task(host, ())
    .unwrap()
    .unwrap()
  let setup = @duckdb_driver.take_duckdb_dispatch(implementation, host, task).unwrap()
  let database = @native_duckdb.load_library(path)
    .unwrap()
    .open_database(@native_duckdb.restricted_open_limits(16777216L))
    .unwrap()
  let runtime = @native_host.start_native_strategy_compute_runtime(
    setup,
    database,
    native_compute_import_limits(),
    100000L,
    16777216L,
  ).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    16777216L +
    @duckdb_driver.configured_strategy_scratch_capacity(setup).unwrap(),
  )
  let setting = database
    .stream_query(
      "SELECT CAST(current_setting('memory_limit') AS VARCHAR)", 1, 1L, 1, 128,
    )
    .unwrap()
  assert_eq(
    setting.next().unwrap(),
    Some({ row_count: 1, columns_json: "[[\"16.0 MiB\"]]", }),
  )
  assert_eq(setting.next().unwrap(), None)
  assert_true(setting.close())
  assert_true(
    database.query_i64(
      "SELECT count(*) FROM (SELECT i % 1000000 AS k, count(*) " +
      "FROM range(5000000) t(i) GROUP BY k)",
    )
    is Err(@native_duckdb.Query(_)),
  )
  assert_false(@strategy.captured_task_completed(run, 1))
  let output = @native_host.execute_native_strategy_compute_runtime(runtime).unwrap()
  assert_true(@strategy.captured_task_completed(run, 1))
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
  assert_true(
    physical_equal(
      @native_host.native_strategy_compute_runtime_output(runtime).unwrap(),
      output,
    ),
  )
  assert_true(
    @native_host.close_native_strategy_compute_runtime(runtime).unwrap(),
  )
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.attempts, 1)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  @host_driver.stop_dispatch_driver(driver)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "native DuckDB memory denial releases the common execution reservation" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let (run, issuer) = captured_graph_fixture()
  let registry = search_registry()
  let revision = native_compute_strategy_selection(run, registry)
  let registration = @strategy.strategy_registration(revision, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let generated = dispatch_test_generated(run)
  let limits = duckdb_dispatch_module_limits()
  let implementation = @duckdb_driver.prepare_duckdb_dispatch_module(
    driver,
    registry,
    registration,
    generated.map(@execution.generated_completion_preparation),
    limits,
  ).unwrap()
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(_context : Unit, task, selected, request) {
          @duckdb_driver.prepare_duckdb_dispatch(
            implementation, task, selected, request,
          )
        },
      ),
    ],
    1,
  ).unwrap()
  let host = @host_driver.open_dispatch_host(
    driver,
    entries,
    limits.capacity,
    100,
    10000,
  ).unwrap()
  let task = @host_driver.prepare_next_installed_task(host, ())
    .unwrap()
    .unwrap()
  let setup = @duckdb_driver.take_duckdb_dispatch(implementation, host, task).unwrap()
  let engine_bytes = 16777216L
  let database = @native_duckdb.load_library(path)
    .unwrap()
    .open_database(@native_duckdb.restricted_open_limits(engine_bytes))
    .unwrap()
  let runtime = @native_host.start_native_strategy_compute_runtime(
    setup,
    database,
    native_compute_import_limits(),
    100000L,
    engine_bytes,
  ).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    engine_bytes +
    @duckdb_driver.configured_strategy_scratch_capacity(setup).unwrap(),
  )
  assert_true(
    database.query_i64(
      "SELECT count(*) FROM (SELECT i % 1000000 AS k, count(*) " +
      "FROM range(5000000) t(i) GROUP BY k)",
    )
    is Err(@native_duckdb.Query(_)),
  )
  assert_false(@strategy.captured_task_completed(run, 1))
  assert_true(
    @native_host.close_native_strategy_compute_runtime(runtime).unwrap(),
  )
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  @host_driver.stop_dispatch_driver(driver)
  @mock.close_mock_query_issuer(issuer)
}
