///|
test "Local capacity profile has independent fixed node text and fragment allowances" {
  let (run, _) = captured_graph_fixture()
  let input = @strategy.captured_task_input(run, 1, 100, 10000).unwrap()
  let generated = query_generated(@execution.producer_read_receiver(input))
  let limits = compute_test_limits()
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let capacity = @execution.generated_sequence_capacity(
    generated, limits, measurement,
  ).unwrap()
  assert_eq(capacity.retained_bytes, 7760000L)
  assert_eq(capacity.execution_bytes, 19116800L)
  assert_true(
    @execution.generated_sequence_capacity(
      generated,
      { ..limits, rows: { ..limits.rows, retained_entries: -1, }, },
      measurement,
    )
    is None,
  )
  assert_true(
    @execution.generated_sequence_capacity(generated, limits, {
      ..measurement,
      max_bytes: -1,
    })
    is None,
  )
}

///|
test "Local reserves physical capacity before execution and releases failed work without erasing upstream retention" {
  let (run, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  let occupied = @resources.reserve_attempt(ledger, 0L, 24240001L, 0L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(captured_graph_local(run, 1) is Err(Physical(RetentionLimit)))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@strategy.next_captured_task(run), Some(1))
  assert_false(@strategy.captured_task_completed(run, 1))
  @resources.settle_reservation(ledger, occupied).unwrap()
  let exact = @resources.reserve_attempt(ledger, 0L, 24240000L, 0L).unwrap()
  captured_graph_local(run, 1).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 24240000L)
  @resources.settle_reservation(ledger, exact).unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_eq(held.held_bytes, 7760000L)
  assert_eq(held.reserved_execution_bytes, 0L)
  assert_true(
    captured_graph_local(run, 2, limits={
      ..compute_test_limits(),
      max_work: 0,
    })
    is Err(Compute(_)),
  )
  let failed = @resources.ledger_usage(ledger)
  assert_eq(failed.held_bytes, held.held_bytes)
  assert_eq(failed.reserved_retention_bytes, 0L)
  assert_eq(failed.reserved_execution_bytes, 0L)
  assert_eq(failed.attempts, held.attempts + 1)
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is Some(_))
  assert_true(@strategy.captured_task_output(run, 2, Step(1)) is None)
  assert_true(@strategy.next_captured_task(run) is None)
}

///|
test "Local working capacity and selected strategy envelope are enforced before starting" {
  let (run, _) = captured_graph_fixture()
  let ordinary = compute_test_limits()
  let ledger = @strategy.captured_dag_ledger(run)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    captured_graph_local(run, 1, limits={
      ..ordinary,
      rows: { ..ordinary.rows, operation_entries: 1000000, },
    })
    is Err(Physical(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 3,
    max_strategies: 1,
    max_work: 100,
    max_revisions: 1,
  }).unwrap()
  let offers = Array::makei(3, index => {
    @strategy.prepare_task_offer(
      run,
      index + 1,
      @connector.capability_registration_at(registry, 0).unwrap(),
      5,
      [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(1L), }],
      { transfer_bytes: 0L, retained_bytes: 0L, execution_bytes: 0L, },
      100,
    ).unwrap()
  })
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None) is Ok(Selected(_)),
  )
  let planned = @resources.ledger_usage(ledger)
  assert_true(
    captured_graph_local(run, 1, supplied_registry=Some(registry))
    is Err(Physical(InvalidCharge)),
  )
  assert_eq(@resources.ledger_usage(ledger), planned)
  assert_false(@strategy.captured_task_completed(run, 1))
}

///|
test "strategy comparison cannot reuse consumed attempt or holding record budgets" {
  for use_holdings in [false, true] {
    let (run, _) = captured_graph_fixture()
    let ledger = @strategy.captured_dag_ledger(run)
    let registry = search_registry()
    @strategy.configure_strategy_search(run, {
      max_offers: 6,
      max_strategies: 8,
      max_work: 1000,
      max_revisions: 2,
    }).unwrap()
    let offers = search_offers(run, registry, [1, 2, 3], Some(1L))
    assert_true(
      @strategy.revise_strategy(run, offers, registry, None) is Ok(Selected(_)),
    )
    if use_holdings {
      let reservation = @resources.reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
      for _ in 0..<8 {
        let holding = @resources.retain_allocation(ledger, reservation, 0L).unwrap()
        @resources.release_allocation(ledger, holding).unwrap()
      }
      @resources.settle_reservation(ledger, reservation).unwrap()
    } else {
      for _ in 0..<8 {
        let reservation = @resources.reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
        @resources.settle_reservation(ledger, reservation).unwrap()
      }
    }
    assert_true(
      @strategy.revise_strategy(run, offers, registry, None) is Ok(NoFeasible),
    )
    for index in 0..<8 {
      assert_eq(
        @strategy.strategy_report_at(run, index).unwrap().rejection,
        if use_holdings {
          Some(@resources.HoldingLimit)
        } else {
          Some(@resources.AttemptLimit)
        },
      )
    }
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}
