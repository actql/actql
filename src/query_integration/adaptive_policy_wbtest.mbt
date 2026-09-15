///|
test "adaptive implementation failure is sticky and revokes old direct dispatch" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let driver = @host_driver.open_dispatch_driver(run)
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let calls = [0]
  let fail = [false]
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(
          _context : Unit,
          task,
          _quantities : @host_driver.TaskEstimateQuantities,
        ) -> Result[Array[@strategy.TaskOffer], String] {
          calls[0] += 1
          if fail[0] {
            return Err("provider-estimate-failed")
          }
          @strategy.prepare_task_offer(
            run,
            task,
            registration,
            1,
            [{ work_slots: [0], milliseconds: Some(1L), }],
            {
              transfer_bytes: 0L,
              retained_bytes: 100L,
              execution_bytes: 2000L,
            },
            100,
          )
          .map(offer => [offer])
          .map_err(_ => "offer-failed")
        },
      ),
    ],
    1,
  ).unwrap()
  let policy = @host_driver.open_adaptive_dispatch(
    driver,
    registry,
    entries,
    [Some(1000), Some(1000), Some(1000)],
    { max_offers: 3, max_strategies: 1, max_work: 1000, max_revisions: 2, },
    0,
  ).unwrap()
  @host_driver.refresh_adaptive_dispatch(policy).unwrap()
  assert_eq(calls[0], 3)
  @host_driver.refresh_adaptive_dispatch(policy).unwrap()
  assert_eq(calls[0], 3)
  // A real reservation changes the state and cannot be erased by reselection.
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 1L, 1L, 1L).unwrap()
  fail[0] = true
  assert_true(
    @host_driver.refresh_adaptive_dispatch(policy)
    is Err(Implementation("provider-estimate-failed")),
  )
  let stopped = @resources.ledger_usage(ledger)
  assert_true(@strategy.next_captured_task(run) is None)
  assert_eq(@strategy.strategy_history_count(run), 1)
  assert_eq(calls[0], 4)
  assert_true(
    @host_driver.refresh_adaptive_dispatch(policy)
    is Err(Implementation("provider-estimate-failed")),
  )
  assert_eq(calls[0], 4)
  assert_eq(@resources.ledger_usage(ledger), stopped)
  @resources.settle_reservation(ledger, reservation).unwrap()
}
