///|
test "installed task recovery is bound to its exact Host even with the same driver and registry" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let revision = channel_test_selection(run, registry)
  let registration = @strategy.strategy_registration(revision, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let channel : @host_driver.DispatchChannel[Int] = @host_driver.open_dispatch_channel(
    driver, registry, registration,
  ).unwrap()
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(_context : Unit, task, revision, request) {
          @host_driver.stage_dispatch_work(channel, task, revision, request, 7)
        },
      ),
    ],
    1,
  ).unwrap()
  let first = @host_driver.open_dispatch_host(
    driver,
    entries,
    dispatch_test_limits().capacity,
    100,
    10000,
  ).unwrap()
  let second = @host_driver.open_dispatch_host(
    driver,
    entries,
    dispatch_test_limits().capacity,
    100,
    10000,
  ).unwrap()
  let task = @host_driver.prepare_next_installed_task(first, ())
    .unwrap()
    .unwrap()
  assert_true(
    @host_driver.prepare_next_installed_task(second, ())
    is Err(Dispatch(PendingTask)),
  )
  assert_true(
    @host_driver.take_installed_task(second, task, channel) is Err(StaleTask),
  )
  assert_eq(@host_driver.take_installed_task(first, task, channel).unwrap(), 7)
  assert_true(
    @host_driver.take_installed_task(first, task, channel) is Err(StaleTask),
  )
  assert_false(@strategy.captured_task_completed(run, 1))
}

///|
test "a returned work token from another run cannot become a prepared task or leave a dispatchable ticket" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let revision = channel_test_selection(run, registry)
  let registration = @strategy.strategy_registration(revision, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let (foreign, _) = captured_graph_fixture()
  let foreign_revision = channel_test_selection(foreign, registry)
  let foreign_driver = @host_driver.open_dispatch_driver(foreign)
  let channel : @host_driver.DispatchChannel[Int] = @host_driver.open_dispatch_channel(
    foreign_driver, registry, registration,
  ).unwrap()
  let foreign_request = @host_driver.prepare_dispatch_inputs(
    foreign_driver,
    1,
    foreign_revision,
    dispatch_test_limits().capacity,
    100,
    10000,
  ).unwrap()
  let foreign_work = @host_driver.stage_dispatch_work(
    channel, 1, foreign_revision, foreign_request, 11,
  ).unwrap()
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(
          _context : Unit,
          _task : Int,
          _revision : @strategy.StrategyRevision,
          _request : @connector.FixedComputeRequest,
        ) -> Result[@host_driver.DispatchWork, Unit] {
          Ok(foreign_work)
        },
      ),
    ],
    1,
  ).unwrap()
  let host = @host_driver.open_dispatch_host(
    driver,
    entries,
    dispatch_test_limits().capacity,
    100,
    10000,
  ).unwrap()
  assert_true(
    @host_driver.prepare_next_installed_task(host, ())
    is Err(Dispatch(StaleTask)),
  )
  assert_false(@host_driver.dispatch_driver_pending(driver))
  assert_true(@strategy.next_captured_task(run) is None)
  assert_false(@strategy.captured_task_completed(run, 1))
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
  // Stopping the miswired Host does not revoke the independent foreign Host.
  let ticket = @host_driver.prepare_dispatch_ticket(
    foreign_driver, 1, foreign_revision,
  ).unwrap()
  assert_eq(
    @host_driver.take_dispatch_work(
      channel, foreign_driver, ticket, foreign_work,
    ).unwrap(),
    11,
  )
}
