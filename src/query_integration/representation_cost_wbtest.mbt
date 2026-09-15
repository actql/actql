///|
test "shared representation capacity is independent of Host result capacity" {
  // X needs 80 bytes. Three task outputs of 100 fit a 1000-byte resource;
  // outputs of 700 do not (X and A must survive until B has completed).
  // Changing only Host retention cannot change that physical-copy constraint.
  for
    (host_bytes, copy_bytes, feasible) in [
      (100L, 100L, true),
      (5000L, 100L, true),
      (100L, 700L, false),
      (5000L, 700L, false),
    ] {
    let (run, _) = captured_graph_fixture()
    let registry = search_registry()
    let registration = @connector.capability_registration_at(registry, 1).unwrap()
    @strategy.configure_strategy_search(run, {
      max_offers: 3,
      max_strategies: 1,
      max_work: 10000,
      max_revisions: 1,
    }).unwrap()
    let profile = @strategy.prepare_resident_profile(
      run,
      registration,
      1000L,
      Some(0L),
      Some(0L),
      Array::make(4, @strategy.ResidentImportEstimate::{
        milliseconds: Some(0L),
        transfer_bytes: 20L,
        scratch_bytes: 100L,
        table_bytes: 80L,
      }),
    ).unwrap()
    let offers = []
    for task in 1..<4 {
      let base = @strategy.prepare_task_offer(
        run,
        task,
        registration,
        1,
        [{ work_slots: [0], milliseconds: Some(1L), }],
        {
          transfer_bytes: 100L,
          retained_bytes: host_bytes,
          execution_bytes: 2000L,
        },
        100,
      ).unwrap()
      assert_true(
        @strategy.resident_task_offer(run, base, profile, -1L)
        is Err(InvalidCapacity),
      )
      offers.push(
        @strategy.resident_task_offer(run, base, profile, copy_bytes).unwrap(),
      )
    }
    let decision = @strategy.revise_strategy(run, offers, registry, None).unwrap()
    if feasible {
      assert_true(decision is Selected(_))
    } else {
      assert_true(decision is NoFeasible)
    }
    // Planning a representation neither creates it nor discounts actual I/O.
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.attempts, 0)
    assert_eq(usage.held_bytes, 0L)
    assert_eq(usage.transferred_bytes, 0L)
  }
}
