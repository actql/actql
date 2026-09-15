///|
fn channel_test_selection(
  run : @strategy.CapturedDAG,
  registry : @connector.CapabilityRegistry,
) -> @strategy.StrategyRevision {
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 4,
  }).unwrap()
  @strategy.revise_strategy(
    run,
    search_offers(run, registry, [1, 2, 3], Some(20L)),
    registry,
    None,
  ).unwrap()
  |> ignore
  @strategy.captured_dag_strategy(run).unwrap()
}

///|
test "typed dispatch slots require exact channel driver ticket and consume only once" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let revision = channel_test_selection(run, registry)
  let registration = @strategy.strategy_registration(revision, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let channel : @host_driver.DispatchChannel[String] = @host_driver.open_dispatch_channel(
    driver, registry, registration,
  ).unwrap()
  let other : @host_driver.DispatchChannel[Int] = @host_driver.open_dispatch_channel(
    driver, registry, registration,
  ).unwrap()
  let request = @host_driver.prepare_dispatch_inputs(
    driver,
    1,
    revision,
    dispatch_test_limits().capacity,
    100,
    10000,
  ).unwrap()
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  let work = @host_driver.stage_dispatch_work(
    channel, 1, revision, request, "owned payload",
  ).unwrap()
  let other_work = @host_driver.stage_dispatch_work(
    other, 1, revision, request, 23,
  ).unwrap()
  assert_true(
    @host_driver.stage_dispatch_work(
      channel, 1, revision, request, "replacement",
    )
    is Err(PendingTask),
  )
  let ticket = @host_driver.prepare_dispatch_ticket(driver, 1, revision).unwrap()
  assert_true(
    @host_driver.take_dispatch_work(other, driver, ticket, work)
    is Err(StaleTask),
  )
  assert_true(
    @host_driver.take_dispatch_work(channel, driver, ticket, other_work)
    is Err(StaleTask),
  )
  let other_driver = @host_driver.open_dispatch_driver(run)
  assert_true(
    @host_driver.take_dispatch_work(channel, other_driver, ticket, work)
    is Err(StaleTask),
  )
  assert_eq(
    @host_driver.take_dispatch_work(channel, driver, ticket, work).unwrap(),
    "owned payload",
  )
  assert_true(
    @host_driver.take_dispatch_work(channel, driver, ticket, work)
    is Err(StaleTask),
  )
  assert_true(
    @host_driver.take_dispatch_work(other, driver, ticket, other_work)
    is Err(StaleTask),
  )
  let after = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_false(@strategy.captured_task_completed(run, 1))
}

///|
test "dispatch staging rejects wrong checked owner selected registration and task" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let revision = channel_test_selection(run, registry)
  let driver = @host_driver.open_dispatch_driver(run)
  let channel : @host_driver.DispatchChannel[Int] = @host_driver.open_dispatch_channel(
    driver,
    registry,
    @strategy.strategy_registration(revision, 1).unwrap(),
  ).unwrap()
  let wrong : @host_driver.DispatchChannel[Int] = @host_driver.open_dispatch_channel(
    driver,
    registry,
    @connector.capability_registration_at(registry, 1).unwrap(),
  ).unwrap()
  let request = @host_driver.prepare_dispatch_inputs(
    driver,
    1,
    revision,
    dispatch_test_limits().capacity,
    100,
    10000,
  ).unwrap()
  assert_true(
    @host_driver.stage_dispatch_work(wrong, 1, revision, request, 1)
    is Err(StaleTask),
  )
  assert_true(
    @host_driver.stage_dispatch_work(channel, 2, revision, request, 1)
    is Err(StaleTask),
  )
  let (foreign, _) = captured_graph_fixture()
  let foreign_revision = channel_test_selection(foreign, registry)
  let foreign_request = @host_driver.prepare_dispatch_inputs(
    @host_driver.open_dispatch_driver(foreign),
    1,
    foreign_revision,
    dispatch_test_limits().capacity,
    100,
    10000,
  ).unwrap()
  assert_true(
    @host_driver.stage_dispatch_work(channel, 1, revision, foreign_request, 1)
    is Err(StaleTask),
  )
  // Invalid preparation does not poison the corrected request or start work.
  @host_driver.stage_dispatch_work(channel, 1, revision, request, 2).unwrap()
  |> ignore
}

///|
test "closing the installation or stopping the driver prevents typed payload recovery" {
  for close_registry in [false, true] {
    let (run, _) = captured_graph_fixture()
    let registry = search_registry()
    let revision = channel_test_selection(run, registry)
    let driver = @host_driver.open_dispatch_driver(run)
    let channel : @host_driver.DispatchChannel[Int] = @host_driver.open_dispatch_channel(
      driver,
      registry,
      @strategy.strategy_registration(revision, 1).unwrap(),
    ).unwrap()
    let request = @host_driver.prepare_dispatch_inputs(
      driver,
      1,
      revision,
      dispatch_test_limits().capacity,
      100,
      10000,
    ).unwrap()
    let work = @host_driver.stage_dispatch_work(
      channel, 1, revision, request, 7,
    ).unwrap()
    let ticket = @host_driver.prepare_dispatch_ticket(driver, 1, revision).unwrap()
    if close_registry {
      @connector.close_capability_registry(registry)
    } else {
      @host_driver.stop_dispatch_driver(driver)
    }
    assert_true(
      @host_driver.take_dispatch_work(channel, driver, ticket, work)
      is Err(StaleTask),
    )
    assert_false(@strategy.captured_task_completed(run, 1))
  }
}

///|
test "reselection replaces only an unstarted typed preparation without restoring its ticket" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let revision = channel_test_selection(run, registry)
  let driver = @host_driver.open_dispatch_driver(run)
  let channel : @host_driver.DispatchChannel[String] = @host_driver.open_dispatch_channel(
    driver,
    registry,
    @strategy.strategy_registration(revision, 1).unwrap(),
  ).unwrap()
  let request = @host_driver.prepare_dispatch_inputs(
    driver,
    1,
    revision,
    dispatch_test_limits().capacity,
    100,
    10000,
  ).unwrap()
  let old = @host_driver.stage_dispatch_work(
    channel, 1, revision, request, "old",
  ).unwrap()
  let old_ticket = @host_driver.prepare_dispatch_ticket(driver, 1, revision).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  @strategy.revise_strategy(
    run,
    search_offers(run, registry, [1, 2, 3], Some(20L)),
    registry,
    None,
  ).unwrap()
  |> ignore
  let replacement = @strategy.captured_dag_strategy(run).unwrap()
  assert_true(
    @host_driver.take_dispatch_work(channel, driver, old_ticket, old)
    is Err(StaleTask),
  )
  @host_driver.check_dispatch_idle(driver).unwrap()
  let new_request = @host_driver.prepare_dispatch_inputs(
    driver,
    1,
    replacement,
    dispatch_test_limits().capacity,
    100,
    10000,
  ).unwrap()
  let work = @host_driver.stage_dispatch_work(
    channel, 1, replacement, new_request, "new",
  ).unwrap()
  let ticket = @host_driver.prepare_dispatch_ticket(driver, 1, replacement).unwrap()
  assert_true(
    @host_driver.take_dispatch_work(channel, driver, ticket, old)
    is Err(StaleTask),
  )
  assert_true(
    @host_driver.take_dispatch_work(channel, driver, old_ticket, work)
    is Err(StaleTask),
  )
  assert_eq(
    @host_driver.take_dispatch_work(channel, driver, ticket, work).unwrap(),
    "new",
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_false(@strategy.captured_task_completed(run, 1))
}
