///|
test "common dispatch tickets belong to one driver even for the same run" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 1,
  }).unwrap()
  @strategy.revise_strategy(
    run,
    search_offers(run, registry, [1, 2, 3], Some(1L)),
    registry,
    None,
  ).unwrap()
  |> ignore
  let revision = @strategy.captured_dag_strategy(run).unwrap()
  let first = @host_driver.open_dispatch_driver(run)
  let second = @host_driver.open_dispatch_driver(run)
  let request = @host_driver.prepare_dispatch_inputs(
    first,
    1,
    revision,
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    },
    100,
    10000,
  ).unwrap()
  assert_true(
    physical_equal(
      @connector.fixed_compute_request_owner(request),
      @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 1).unwrap(),
    ),
  )
  assert_eq(@connector.fixed_compute_request_input_count(request), 1)
  assert_true(
    physical_equal(
      @execution.fixed_relation_read_completed(
        @connector.fixed_compute_request_input(request, 0).unwrap(),
      ).unwrap(),
      @strategy.captured_task_input(run, 1, 100, 10000).unwrap(),
    ),
  )
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(
    @host_driver.prepare_dispatch_ticket(first, 2, revision) is Err(StaleTask),
  )
  let ticket = @host_driver.prepare_dispatch_ticket(first, 1, revision).unwrap()
  assert_eq(@host_driver.dispatch_ticket_task(ticket), 1)
  assert_true(
    physical_equal(@host_driver.dispatch_ticket_revision(ticket), revision),
  )
  assert_true(@host_driver.dispatch_driver_pending(first))
  assert_false(@host_driver.dispatch_driver_pending(second))
  assert_true(
    @host_driver.consume_dispatch_ticket(second, ticket) is Err(StaleTask),
  )
  assert_true(@host_driver.check_dispatch_idle(first) is Err(PendingTask))
  @host_driver.consume_dispatch_ticket(first, ticket).unwrap()
  assert_false(@host_driver.dispatch_driver_pending(first))
  assert_true(
    @host_driver.consume_dispatch_ticket(first, ticket) is Err(StaleTask),
  )
  // Dispatch ownership is not task execution or resource admission.
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), before)
  assert_false(@strategy.captured_task_completed(run, 1))
}

///|
test "stopping a common dispatcher revokes pending dispatch without refunding history" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 1,
  }).unwrap()
  @strategy.revise_strategy(
    run,
    search_offers(run, registry, [1, 2, 3], Some(1L)),
    registry,
    None,
  ).unwrap()
  |> ignore
  let revision = @strategy.captured_dag_strategy(run).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let ticket = @host_driver.prepare_dispatch_ticket(driver, 1, revision).unwrap()
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  @host_driver.stop_dispatch_driver(driver)
  assert_false(@host_driver.dispatch_driver_pending(driver))
  assert_true(@strategy.next_captured_task(run) is None)
  assert_true(
    @host_driver.consume_dispatch_ticket(driver, ticket) is Err(StaleTask),
  )
  assert_true(
    @host_driver.prepare_dispatch_ticket(driver, 1, revision) is Err(StaleTask),
  )
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), before)
  assert_true(
    physical_equal(@strategy.captured_dag_strategy(run).unwrap(), revision),
  )
}
