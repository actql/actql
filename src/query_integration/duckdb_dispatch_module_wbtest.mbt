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
  assert_true(
    install(swapped.map(@execution.generated_completion_preparation))
    is Err(InvalidConfiguration),
  )
  let implementation = install(
    generated.map(@execution.generated_completion_preparation),
  ).unwrap()
  let other = install(
    generated.map(@execution.generated_completion_preparation),
  ).unwrap()
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
  assert_eq(
    @duckdb_driver.configured_strategy_output_file_bytes(setup),
    Some(0L),
  )
  for bytes in [0L, 50L] {
    assert_true(
      @duckdb_driver.start_configured_strategy_compute_host(
        setup,
        _ => false,
        100L,
        2000L,
        retained_storage=(bytes, () => true),
      )
      is Err(Physical(InvalidCharge)),
    )
  }
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
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
    dispatch_test_generated(run).map(
      @execution.generated_completion_preparation,
    ),
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

///|
test "DuckDB preRun module keeps its original preparation and refuses invalid output before charging" {
  let (run, issuer) = captured_graph_fixture()
  let graph = @strategy.captured_dag_graph(run)
  let ledger = @strategy.captured_dag_ledger(run)
  let registry = search_registry()
  let registration = @connector.capability_registration_at(registry, 1).unwrap()
  let completions = dispatch_test_generated(run).map(
    @execution.generated_completion_preparation,
  )
  let limits = duckdb_dispatch_module_limits()
  let before = @resources.ledger_usage(ledger)
  for invalid in [(0L, None), (2147483648L, None), (1L, Some(-1L))] {
    assert_true(
      @duckdb_driver.prepare_duckdb_dispatch_plan(
        graph,
        ledger,
        registry,
        registration,
        completions,
        limits,
        retained_output=Some(invalid),
      )
      is Err(InvalidConfiguration),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
  }
  let original = @duckdb_driver.prepare_duckdb_dispatch_plan(
    graph,
    ledger,
    registry,
    registration,
    completions,
    limits,
    retained_output=Some((1L, Some(0L))),
  ).unwrap()
  let after = @resources.ledger_usage(ledger)
  completions.clear()
  let installed_original = @duckdb_driver.bind_duckdb_dispatch_plan(
    @host_driver.open_dispatch_driver(run),
    original,
  ).unwrap()
  assert_true(
    physical_equal(
      @duckdb_driver.duckdb_dispatch_original_preparation(installed_original),
      original,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), after)
  assert_true(
    @duckdb_driver.duckdb_dispatch_rejection(installed_original, 1) is None,
  )
  assert_true(
    @duckdb_driver.configure_duckdb_retained_output(
      installed_original,
      2L,
      None,
    )
    is Err(InvalidConfiguration),
  )
  @strategy.stop_captured_dag(run)
  for task in 0..<@strategy.graph_task_count(graph) {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
  @connector.close_capability_registry(registry)
}
