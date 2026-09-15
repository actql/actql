///|
fn adaptive_profiles() -> Array[@dbhost.DispatchEstimateProfile] {
  Array::makei(3, index => {
    local_rates: [
      {
        work_slots: [0, 1, 2, 3, 4],
        fixed_ms: Some(if index == 2 { 0L } else { 1L }),
        per_row_ms: Some(if index == 2 { 2L } else { 0L }),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_rates: [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
        fixed_ms: Some(if index == 2 { 3L } else { 100L }),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_capacity: {
      transfer_bytes: 100000L,
      retained_bytes: 100L,
      execution_bytes: 134217728L,
    },
    output_rows_per_mille: Some(1000),
  })
}

///|
fn adaptive_host(
  run : @strategy.CapturedDAG,
  registry : @planning.CapabilityRegistry,
) -> @dbhost.StrategyHostDispatch raise {
  @dbhost.configure_strategy_dispatch(
    run,
    registry,
    @planning.capability_registration_at(registry, 0).unwrap(),
    @planning.capability_registration_at(registry, 1).unwrap(),
    dispatch_test_generated(run),
    dispatch_test_limits(),
  ).unwrap()
}

///|
test "observed completion revises only the unstarted suffix without resetting resources" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let host = adaptive_host(run, registry)
  let profiles = adaptive_profiles()
  @dbhost.configure_dispatch_estimates(host, profiles, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 3,
  }).unwrap()
  // The installed policy owns its nested arrays, not the caller's mutations.
  profiles[0].local_rates[0].work_slots[0] = 99
  @dbhost.refresh_dispatch_estimates(host).unwrap()
  let first = @strategy.strategy_history_at(run, 0).unwrap()
  let native_reg = @planning.capability_registration_at(registry, 1).unwrap()
  let local_reg = @planning.capability_registration_at(registry, 0).unwrap()
  assert_true(
    physical_equal(
      @strategy.strategy_registration(first, 3).unwrap(),
      native_reg,
    ),
  )
  let ledger = @strategy.captured_dag_ledger(run)
  let before = @resources.ledger_usage(ledger)
  @dbhost.refresh_dispatch_estimates(host).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  let a = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
  @dbhost.execute_local_dispatch(a).unwrap()
  let after_a = @resources.ledger_usage(ledger)
  let b = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
  let second = @strategy.strategy_history_at(run, 1).unwrap()
  // A really produced one row: C's estimate falls from 4 to 2, below native 3.
  assert_true(
    physical_equal(
      @strategy.strategy_registration(second, 3).unwrap(),
      local_reg,
    ),
  )
  assert_true(
    physical_equal(
      @strategy.strategy_registration(second, 1).unwrap(),
      local_reg,
    ),
  )
  let revised = @resources.ledger_usage(ledger)
  assert_eq({ ..revised, planning_work: 0, }, { ..after_a, planning_work: 0, })
  assert_true(revised.planning_work > after_a.planning_work)
  @dbhost.execute_local_dispatch(b).unwrap()
  let c = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
  assert_false(@dbhost.dispatch_is_native(c))
  @dbhost.execute_local_dispatch(c).unwrap()
  assert_true(@dbhost.prepare_next_dispatch(host) is Ok(None))
  assert_eq(@strategy.strategy_history_count(run), 3)
}

///|
test "unknown downstream size defers and cannot fall through to an old selection" {
  let (run, _) = captured_graph_fixture()
  let host = adaptive_host(run, search_registry())
  let profiles = adaptive_profiles()
  profiles[2].local_rates[0] = {
    ..profiles[2].local_rates[0],
    per_wire_byte_ms: Some(1L),
  }
  @dbhost.configure_dispatch_estimates(host, profiles, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 3,
  }).unwrap()
  assert_true(@dbhost.prepare_next_dispatch(host) is Err(NoStrategy))
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.attempts, 0)
  assert_true(@dbhost.prepare_next_dispatch(host) is Err(NoStrategy))
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), usage)
}

///|
test "adaptive estimate overflow and revision exhaustion do not start more work" {
  for overflow in [true, false] {
    let (run, _) = captured_graph_fixture()
    let host = adaptive_host(run, search_registry())
    let profiles = adaptive_profiles()
    if overflow {
      profiles[0].local_rates[0] = {
        ..profiles[0].local_rates[0],
        per_row_ms: Some(9223372036854775807L),
      }
    }
    @dbhost.configure_dispatch_estimates(host, profiles, {
      max_offers: 6,
      max_strategies: 8,
      max_work: 1000,
      max_revisions: 1,
    }).unwrap()
    if overflow {
      assert_true(@dbhost.prepare_next_dispatch(host) is Err(EstimateOverflow))
    } else {
      let first = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
      @dbhost.execute_local_dispatch(first).unwrap()
      assert_true(
        @dbhost.prepare_next_dispatch(host) is Err(Search(RevisionLimit)),
      )
      assert_true(@strategy.captured_task_output(run, 1, Step(1)) is Some(_))
    }
    let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_true(@dbhost.prepare_next_dispatch(host) is Err(_))
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
      before,
    )
    assert_false(@strategy.captured_task_completed(run, 2))
  }
}
