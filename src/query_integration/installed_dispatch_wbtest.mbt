///|
test "installed preparation cannot publish tickets after registry close or run stop" {
  for revoke in [false, true] {
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
    let registration = @strategy.strategy_registration(revision, 1).unwrap()
    let driver = @host_driver.open_dispatch_driver(run)
    let invoked = Ref(0)
    let entries : Array[
      (
        @connector.CapabilityRegistration,
        (Unit, Int, @strategy.StrategyRevision, @connector.FixedComputeRequest) -> Result[
          Int,
          String,
        ],
      ),
    ] = [
      (
        registration,
        fn(_context, task, _revision, _request) {
          invoked.val += 1
          if revoke {
            @connector.close_capability_registry(registry)
          } else {
            @host_driver.stop_dispatch_driver(driver)
          }
          Ok(task)
        },
      ),
    ]
    let installed = @connector.install_capability_implementations(
      registry, entries, 1,
    ).unwrap()
    // The Host owns a snapshot, not the caller's mutable registration array.
    entries.clear()
    let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    let result = @host_driver.prepare_installed_dispatch(
      driver,
      installed,
      (),
      1,
      revision,
      dispatch_test_limits().capacity,
      100,
      10000,
    )
    if revoke {
      assert_true(result is Err(MissingImplementation))
    } else {
      assert_true(result is Err(Dispatch(StaleTask)))
    }
    assert_eq(invoked.val, 1)
    assert_false(@host_driver.dispatch_driver_pending(driver))
    assert_false(@strategy.captured_task_completed(run, 1))
    let after = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(after.attempts, before.attempts)
    assert_eq(after.transferred_bytes, before.transferred_bytes)
  }
}
