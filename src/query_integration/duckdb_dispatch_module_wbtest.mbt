///|
fn duckdb_dispatch_module_limits() -> @duckdb_driver.DuckDBDispatchLimits {
  let limits = dispatch_test_limits()
  {
    capacity: limits.capacity,
    query: limits.native_query,
    join_validation: limits.join_validation,
    candidate_work: limits.candidate_work,
    execution: limits.native,
    transport: limits.transport,
  }
}

///|
test "DuckDB installed dispatch retains exact sequences and cannot exchange module payloads" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let revision = channel_test_selection(run, registry)
  let registration = @strategy.strategy_registration(revision, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let generated = dispatch_test_generated(run)
  let limits = duckdb_dispatch_module_limits()
  let install = fn(sequences) {
    @duckdb_driver.prepare_duckdb_dispatch_module(
      driver, registry, registration, sequences, limits,
    )
  }
  assert_true(install([]) is Err(InvalidConfiguration))
  let swapped = generated.copy()
  swapped[0] = generated[1]
  assert_true(install(swapped) is Err(InvalidConfiguration))
  let implementation = install(generated).unwrap()
  let other = install(generated).unwrap()
  generated.clear()
  assert_true(
    @duckdb_driver.duckdb_dispatch_rejection(implementation, 1) is None,
  )
  assert_true(
    @duckdb_driver.duckdb_dispatch_rejection(implementation, 0)
    is Some("invalid_task"),
  )
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(_context : Unit, task, revision, request) {
          @duckdb_driver.prepare_duckdb_dispatch(
            implementation, task, revision, request,
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
  assert_true(
    @duckdb_driver.take_duckdb_dispatch(other, host, task)
    is Err(Dispatch(StaleTask)),
  )
  let setup = @duckdb_driver.take_duckdb_dispatch(implementation, host, task).unwrap()
  let (owned_run, index) = @duckdb_driver.configured_strategy_compute_graph(
    setup,
  )
  assert_true(physical_equal(owned_run, run))
  assert_eq(index, 1)
  assert_true(
    @duckdb_driver.take_duckdb_dispatch(implementation, host, task)
    is Err(Dispatch(StaleTask)),
  )
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
  assert_false(@strategy.captured_task_completed(run, 1))
  @host_driver.stop_dispatch_driver(driver)
}

///|
test "DuckDB preparation rejects foreign input ownership before candidate preflight" {
  let (run, _) = captured_graph_fixture()
  let (foreign, _) = captured_graph_fixture()
  let registry = search_registry()
  let revision = channel_test_selection(run, registry)
  let foreign_revision = channel_test_selection(foreign, registry)
  let registration = @strategy.strategy_registration(revision, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let foreign_driver = @host_driver.open_dispatch_driver(foreign)
  let limits = duckdb_dispatch_module_limits()
  let implementation = @duckdb_driver.prepare_duckdb_dispatch_module(
    driver,
    registry,
    registration,
    dispatch_test_generated(run),
    limits,
  ).unwrap()
  let foreign_request = @host_driver.prepare_dispatch_inputs(
    foreign_driver,
    1,
    foreign_revision,
    limits.capacity,
    100,
    10000,
  ).unwrap()
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(
    @duckdb_driver.prepare_duckdb_dispatch(
      implementation, 1, revision, foreign_request,
    )
    is Err(ForeignSelection),
  )
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), before)
  let request = @host_driver.prepare_dispatch_inputs(
    driver,
    1,
    revision,
    limits.capacity,
    100,
    10000,
  ).unwrap()
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(
    @duckdb_driver.prepare_duckdb_dispatch(
      implementation, 1, foreign_revision, request,
    )
    is Err(ForeignSelection),
  )
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), before)
}
