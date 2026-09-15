///|
test "search request correction spends work without consuming a revision" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 1,
  }).unwrap()
  let incomplete = search_offers(run, registry, [1, 3], Some(20L))
  let ledger = @strategy.captured_dag_ledger(run)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @strategy.revise_strategy(run, incomplete, registry, None)
    is Err(MissingTask(2)),
  )
  assert_true(
    @resources.ledger_usage(ledger).planning_work > before.planning_work,
  )
  let offers = search_offers(run, registry, [1, 2, 3], Some(20L))
  guard @strategy.revise_strategy(run, offers, registry, None)
    is Ok(Selected(revision)) else {
    abort("corrected request")
  }
  assert_eq(@strategy.strategy_revision_number(revision), 1)
  assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
}

///|
test "enumeration Overflow revokes dispatch and cannot be retried by correcting costs" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let host = adaptive_host(run, registry)
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 3,
  }).unwrap()
  let offers = search_offers(run, registry, [1, 2, 3], Some(20L))
  @strategy.revise_strategy(run, offers, registry, None).unwrap() |> ignore
  let old = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 1L, 0L, 0L).unwrap()
  @resources.charge_transfer(ledger, reservation, 1L).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  let excessive = []
  for task in 1..<4 {
    excessive.push(
      @strategy.prepare_task_offer(
        run,
        task,
        @planning.capability_registration_at(registry, 0).unwrap(),
        1,
        [{ work_slots: [0], milliseconds: Some(9223372036854775807L), }],
        { transfer_bytes: 0L, retained_bytes: 100L, execution_bytes: 1000L, },
        100,
      ).unwrap(),
    )
  }
  assert_true(
    @strategy.revise_strategy(run, excessive, registry, None) is Err(Overflow),
  )
  assert_true(@dbhost.execute_local_dispatch(old) is Err(StaleTask))
  assert_true(@dbhost.prepare_next_dispatch(host) is Err(NoStrategy))
  let spent = @resources.ledger_usage(ledger)
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None)
    is Err(UnchangedState),
  )
  assert_eq(@resources.ledger_usage(ledger), spent)
  assert_eq(spent.transferred_bytes, 1L)
  assert_eq(@strategy.strategy_history_count(run), 1)
  assert_eq(@strategy.next_captured_task(run), Some(1)) // not a stopped Run
}

///|
test "accepted search failure revokes old and new dispatch without resetting history" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let host = adaptive_host(run, registry)
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 50,
    max_revisions: 3,
  }).unwrap()
  let offers = search_offers(run, registry, [1, 2, 3], Some(20L))
  @strategy.revise_strategy(
    run,
    [offers[0], offers[2], offers[4]],
    registry,
    None,
  ).unwrap()
  |> ignore
  let old = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 1L, 0L, 0L).unwrap()
  @resources.charge_transfer(ledger, reservation, 1L).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None)
    is Err(Ledger(PlanningLimit)),
  )
  assert_true(@dbhost.execute_local_dispatch(old) is Err(StaleTask))
  assert_true(@dbhost.prepare_next_dispatch(host) is Err(NoStrategy))
  let spent = @resources.ledger_usage(ledger)
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None)
    is Err(UnchangedState),
  )
  assert_eq(@resources.ledger_usage(ledger), spent)
  assert_eq(spent.transferred_bytes, 1L)
  assert_eq(@strategy.strategy_history_count(run), 1)
  assert_false(@strategy.captured_task_completed(run, 1))
}
