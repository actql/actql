///|
test "Local connector installation validates task owners and cannot exchange prepared channels" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let revision = channel_test_selection(run, registry)
  let registration = @strategy.strategy_registration(revision, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let generated = dispatch_test_generated(run)
  let limits = dispatch_test_limits()
  let install = fn(sequences) {
    @local_driver.prepare_local_dispatch_module(
      driver,
      registry,
      registration,
      sequences,
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
    )
  }
  assert_true(install([]) is Err(Configuration(ForeignPreparation)))
  let swapped = generated.copy()
  swapped[0] = generated[1]
  assert_true(install(swapped) is Err(Configuration(ForeignPreparation)))
  let implementation = install(generated).unwrap()
  let other = install(generated).unwrap()
  generated.clear()
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(_context : Unit, task, revision, request) {
          @local_driver.prepare_local_dispatch(
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
  let ledger = @strategy.captured_dag_ledger(run)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_true(
    @local_driver.execute_local_dispatch(other, host, task)
    is Err(Dispatch(StaleTask)),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  @local_driver.execute_local_dispatch(implementation, host, task).unwrap()
  assert_true(@strategy.captured_task_completed(run, 1))
  assert_true(
    @local_driver.execute_local_dispatch(implementation, host, task)
    is Err(Dispatch(StaleTask)),
  )
  let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  // The source fixture is [3, 1, 2]; A's id > 2 keeps exactly [3].
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3.0)))
  @strategy.close_captured_task_output(run, 1)
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
}
