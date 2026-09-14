///|
test "priority uses original positions through partial and complete rejection" {
  for held in [24000000L, 31999901L] {
    for duration in [None, Some(9L)] {
      let (run, _) = captured_graph_fixture()
      let registry = search_registry()
      @strategy.configure_strategy_search(run, {
        max_offers: 6,
        max_strategies: 8,
        max_work: 1000,
        max_revisions: 1,
      }).unwrap()
      let ledger = @strategy.captured_dag_ledger(run)
      let reservation = @strategy.reserve_attempt(ledger, 0L, held, 0L).unwrap()
      let holding = @strategy.retain_allocation(ledger, reservation, held).unwrap()
      @strategy.settle_reservation(ledger, reservation).unwrap()
      let offers = search_offers(run, registry, [1, 2, 3], duration)
      let decision = @strategy.revise_strategy(
        run,
        offers,
        registry,
        Some([7, 6, 5, 4, 3, 2, 1, 0]),
      ).unwrap()
      if held == 24000000L {
        guard decision is Selected(revision) else {
          abort("feasible original position seven")
        }
        assert_eq(@strategy.strategy_assessment(revision).position, 7)
      } else {
        assert_true(decision is NoFeasible)
      }
      assert_eq(@strategy.strategy_report_count(run), 8)
      @strategy.release_allocation(ledger, holding).unwrap()
    }
  }
}

///|
test "invalid full priority is correctable and complete ties honor original position" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 1,
  }).unwrap()
  let offers = search_offers(run, registry, [1, 2, 3], Some(9L))
  for invalid in [[7], [8, 6, 5, 4, 3, 2, 1, 0], [7, 7, 5, 4, 3, 2, 1, 0]] {
    assert_true(
      @strategy.revise_strategy(run, offers, registry, Some(invalid))
      is Err(InvalidPreference),
    )
  }
  guard @strategy.revise_strategy(
      run,
      offers,
      registry,
      Some([5, 7, 6, 4, 3, 2, 1, 0]),
    ).unwrap()
    is Selected(revision) else {
    abort("tie")
  }
  assert_eq(@strategy.strategy_assessment(revision).position, 5)
  assert_eq(@strategy.strategy_revision_number(revision), 1)
}
