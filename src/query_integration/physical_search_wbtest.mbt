///|
fn search_registry() -> @planning.CapabilityRegistry {
  @planning.prepare_capability_registry(
    [
      { name: "local", acquisition: false, fixed_compute: true, },
      { name: "duckdb", acquisition: false, fixed_compute: true, },
    ],
    2,
    100,
  ).unwrap()
}

///|
fn search_offers(
  run : @strategy.CapturedDAG,
  registry : @planning.CapabilityRegistry,
  tasks : Array[Int],
  transfer_ms : Int64?,
) -> Array[@strategy.TaskOffer] {
  let result = []
  for task in tasks {
    result.push(
      @strategy.prepare_task_offer(
        run,
        task,
        @planning.capability_registration_at(registry, 0).unwrap(),
        5,
        [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(10L), }],
        {
          transfer_bytes: 0L,
          retained_bytes: 8000000L,
          execution_bytes: 64000000L,
        },
        100,
      ).unwrap(),
    )
    result.push(
      @strategy.prepare_task_offer(
        run,
        task,
        @planning.capability_registration_at(registry, 1).unwrap(),
        8,
        [
          { work_slots: [0, 2, 3, 5, 6, 7], milliseconds: Some(1L), },
          { work_slots: [1, 4], milliseconds: transfer_ms, },
        ],
        {
          transfer_bytes: 100000L,
          retained_bytes: 100L,
          execution_bytes: 134217728L,
        },
        100,
      ).unwrap(),
    )
  }
  result
}

///|
test "whole strategy includes transfer costs and revises only after new completion" {
  let (run, _issuer) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 3,
  }).unwrap()
  let offers = search_offers(run, registry, [1, 2, 3], Some(20L))
  guard @strategy.revise_strategy(run, offers, registry, None).unwrap()
    is Selected(first) else {
    abort("first")
  }
  assert_eq(@strategy.strategy_assessment(first).duration, @cost.Complete(30L))
  for task in 1..<4 {
    assert_true(
      physical_equal(
        @strategy.strategy_registration(first, task).unwrap(),
        @planning.capability_registration_at(registry, 0).unwrap(),
      ),
    )
  }
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None)
    is Err(UnchangedState),
  )
  // Registry identity, not its equal spelling, binds the actual realization.
  assert_true(captured_graph_local(run, 1) is Err(ForeignCandidate))
  captured_graph_local(run, 1, supplied_registry=Some(registry)).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  let previous = @strategy.reserve_attempt(ledger, 1L, 0L, 0L).unwrap()
  @strategy.charge_transfer(ledger, previous, 1L).unwrap()
  @strategy.mark_cleanup_pending(ledger, previous).unwrap()
  let next = search_offers(run, registry, [2, 3], Some(1L))
  guard @strategy.revise_strategy(run, next, registry, None).unwrap()
    is Selected(second) else {
    abort("second")
  }
  assert_eq(@strategy.strategy_generation(second), 1)
  assert_eq(@strategy.strategy_revision_number(second), 2)
  assert_eq(@strategy.strategy_assessment(second).duration, @cost.Complete(4L))
  assert_eq(@strategy.strategy_usage_before(second).transferred_bytes, 1L)
  assert_true(@strategy.reservation_pending(previous))
  assert_true(
    physical_equal(
      @strategy.strategy_registration(second, 1).unwrap(),
      @strategy.strategy_registration(first, 1).unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      @strategy.strategy_registration(second, 3).unwrap(),
      @planning.capability_registration_at(registry, 1).unwrap(),
    ),
  )
  assert_true(
    captured_graph_local(run, 2, supplied_registry=Some(registry))
    is Err(ForeignCandidate),
  )
  assert_eq(@strategy.ledger_usage(ledger).transferred_bytes, 1L)
}

///|
test "unknown work defers without policy and all assignments pay repeated transfer" {
  for preferred in [false, true] {
    let (run, _) = captured_graph_fixture()
    let registry = search_registry()
    @strategy.configure_strategy_search(run, {
      max_offers: 6,
      max_strategies: 8,
      max_work: 1000,
      max_revisions: 1,
    }).unwrap()
    let offers = search_offers(run, registry, [1, 2, 3], None)
    let choice = @strategy.revise_strategy(
      run,
      offers,
      registry,
      if preferred {
        Some([7, 6, 5, 4, 3, 2, 1, 0])
      } else {
        None
      },
    ).unwrap()
    if preferred {
      guard choice is Selected(revision) else { abort("Host priority") }
      assert_eq(@strategy.strategy_assessment(revision).duration, @cost.Unknown)
      assert_eq(@strategy.strategy_assessment(revision).transfer_bytes, 300000L)
    } else {
      assert_true(choice is Deferred)
    }
  }
}

///|
test "search limits and duplicate work cannot be bypassed by another revision" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 7,
    max_work: 1000,
    max_revisions: 1,
  }).unwrap()
  let offers = search_offers(run, registry, [1, 2, 3], Some(1L))
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None) is Err(StrategyLimit),
  )
  let work = @strategy.ledger_usage(@strategy.captured_dag_ledger(run)).planning_work
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None)
    is Err(UnchangedState),
  )
  assert_eq(
    @strategy.ledger_usage(@strategy.captured_dag_ledger(run)).planning_work,
    work,
  )
  assert_true(
    @strategy.prepare_task_offer(
      run,
      1,
      @planning.capability_registration_at(registry, 0).unwrap(),
      1,
      [
        { work_slots: [0], milliseconds: Some(1L), },
        { work_slots: [0], milliseconds: Some(1L), },
      ],
      { transfer_bytes: 0L, retained_bytes: 0L, execution_bytes: 0L, },
      100,
    )
    is Err(Cost(DuplicateSlot(0))),
  )
}

///|
test "pending physical reservations reject assignments and real release permits bounded reconsideration" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 2,
  }).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  let reserved = @strategy.reserve_attempt(ledger, 0L, 31999901L, 0L).unwrap()
  let holding = @strategy.retain_allocation(ledger, reserved, 31999901L).unwrap()
  @strategy.settle_reservation(ledger, reserved).unwrap()
  let offers = search_offers(run, registry, [1, 2, 3], Some(1L))
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None) is Ok(NoFeasible),
  )
  assert_eq(@strategy.strategy_report_count(run), 8)
  for i in 0..<8 {
    assert_true(
      @strategy.strategy_report_at(run, i).unwrap().rejection
      is Some(RetentionLimit),
    )
  }
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None)
    is Err(UnchangedState),
  )
  @strategy.release_allocation(ledger, holding).unwrap()
  guard @strategy.revise_strategy(run, offers, registry, None).unwrap()
    is Selected(revision) else {
    abort("released capacity")
  }
  assert_eq(
    @strategy.strategy_assessment(revision).duration,
    @cost.Complete(6L),
  )
  assert_eq(@strategy.strategy_history_count(run), 1)
  assert_eq(
    @strategy.strategy_revision_number(
      @strategy.strategy_history_at(run, 0).unwrap(),
    ),
    2,
  )
}

///|
test "deferred selection revokes dispatch without forgetting completed placement" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 3,
  }).unwrap()
  let first_offers = search_offers(run, registry, [1, 2, 3], Some(20L))
  guard @strategy.revise_strategy(run, first_offers, registry, None).unwrap()
    is Selected(first) else {
    abort("initial selection")
  }
  captured_graph_local(run, 1, supplied_registry=Some(registry)).unwrap()
  let unknown = search_offers(run, registry, [2, 3], None)
  assert_true(
    @strategy.revise_strategy(run, unknown, registry, None) is Ok(Deferred),
  )
  assert_true(
    captured_graph_local(run, 2, supplied_registry=Some(registry))
    is Err(ForeignCandidate),
  )
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @strategy.reserve_attempt(ledger, 1L, 0L, 0L).unwrap()
  @strategy.charge_transfer(ledger, reservation, 1L).unwrap()
  @strategy.settle_reservation(ledger, reservation).unwrap()
  let known = search_offers(run, registry, [2, 3], Some(1L))
  guard @strategy.revise_strategy(run, known, registry, None).unwrap()
    is Selected(last) else {
    abort("selection after new resource state")
  }
  assert_true(
    physical_equal(
      @strategy.strategy_registration(first, 1).unwrap(),
      @strategy.strategy_registration(last, 1).unwrap(),
    ),
  )
  assert_eq(@strategy.strategy_usage_before(last).transferred_bytes, 1L)
}
