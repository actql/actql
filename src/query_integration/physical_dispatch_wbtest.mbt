///|
fn dispatch_test_limits() -> @dbhost.TaskDispatchLimits {
  {
    input_entries: 100,
    input_name_bytes: 10000,
    candidate_work: 100,
    join_validation: { max_rows: 100, max_work: 1000, max_entries: 1000, },
    capacity: {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    },
    local_execution: compute_test_limits(),
    guards: {
      max_work: 10000,
      max_bytes: 10000,
      max_nodes: 10000,
      max_depth: 100,
    },
    native_query: native_compile_limits(),
    native: fixed_compute_attempt_limits(),
    transport: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_columns: 10,
      max_rows: 100,
      max_text_bytes: 100000,
    },
  }
}

///|
fn dispatch_test_generated(
  run : @strategy.CapturedDAG,
) -> Array[@execution.GeneratedSequence] raise {
  let graph = @strategy.captured_dag_graph(run)
  Array::makei(@strategy.graph_task_count(graph) - 1, index => {
    let owner = @strategy.graph_task_owner(graph, index + 1).unwrap()
    task_test_generated(owner)
  })
}

///|
test "installed dispatch follows exact registration not its label or registry position" {
  let (run, _) = captured_graph_fixture()
  let registry = @connector.prepare_capability_registry(
    [
      { name: "local", acquisition: false, fixed_compute: true, },
      { name: "duckdb", acquisition: false, fixed_compute: true, },
    ],
    2,
    100,
  ).unwrap()
  // Deliberately label the DuckDB implementation local and put Local second.
  // These are diagnostics only, not provider selection instructions.
  let local_entry = @connector.capability_registration_at(registry, 1).unwrap()
  let native = @connector.capability_registration_at(registry, 0).unwrap()
  let host = @dbhost.configure_strategy_dispatch(
    run,
    registry,
    local_entry,
    native,
    dispatch_test_generated(run),
    dispatch_test_limits(),
  ).unwrap()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 4,
  }).unwrap()
  let offers = []
  for task in [1, 2, 3] {
    offers.push(
      @strategy.prepare_task_offer(
        run,
        task,
        local_entry,
        1,
        [{ work_slots: [0], milliseconds: Some(1L), }],
        {
          transfer_bytes: 0L,
          retained_bytes: 8000000L,
          execution_bytes: 64000000L,
        },
        100,
      ).unwrap(),
    )
  }
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None) is Ok(Selected(_)),
  )
  for task in [1, 2, 3] {
    let dispatch = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
    assert_eq(@dbhost.dispatch_task(dispatch), task)
    assert_true(
      physical_equal(
        @dbhost.dispatch_registration(dispatch).unwrap(),
        @dbhost.dispatch_local_registration(host),
      ),
    )
    @dbhost.execute_synchronous_dispatch(dispatch).unwrap()
  }
  assert_eq(
    @execution.completed_row_count(
      @strategy.captured_task_output(run, 3, Step(1)).unwrap(),
    ),
    1,
  )
}

///|
test "dispatch requires exact generated owners and consumes checked-ready tasks once" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let local_reg = @connector.capability_registration_at(registry, 0).unwrap()
  let native_reg = @connector.capability_registration_at(registry, 1).unwrap()
  let generated = dispatch_test_generated(run)
  let (foreign, _) = captured_graph_fixture()
  assert_true(
    @dbhost.configure_strategy_dispatch(
      run,
      registry,
      local_reg,
      native_reg,
      dispatch_test_generated(foreign),
      dispatch_test_limits(),
    )
    is Err(InvalidConfiguration),
  )
  let host = @dbhost.configure_strategy_dispatch(
    run,
    registry,
    local_reg,
    native_reg,
    generated,
    dispatch_test_limits(),
  ).unwrap()
  // Mutating the caller's array cannot replace the already bound implementations.
  generated[0] = dispatch_test_generated(foreign)[0]
  assert_true(@dbhost.prepare_next_dispatch(host) is Err(NoStrategy))
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 4,
  }).unwrap()
  assert_true(
    @strategy.revise_strategy(
      run,
      search_offers(run, registry, [1, 2, 3], Some(20L)),
      registry,
      None,
    )
    is Ok(Selected(_)),
  )
  for task in [1, 2, 3] {
    let prepared = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
    assert_eq(@dbhost.dispatch_task(prepared), task)
    assert_true(
      physical_equal(
        @dbhost.dispatch_registration(prepared).unwrap(),
        @dbhost.dispatch_local_registration(host),
      ),
    )
    assert_true(@dbhost.prepare_next_dispatch(host) is Err(PendingTask))
    @dbhost.execute_synchronous_dispatch(prepared).unwrap()
    assert_true(
      @dbhost.execute_synchronous_dispatch(prepared) is Err(StaleTask),
    )
  }
  assert_true(@dbhost.prepare_next_dispatch(host) is Ok(None))
  assert_eq(
    @execution.completed_row_count(
      @strategy.captured_task_output(run, 3, Step(1)).unwrap(),
    ),
    1,
  )
}

///|
test "a replaced unstarted strategy invalidates a prepared dispatch without starting either candidate" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let host = @dbhost.configure_strategy_dispatch(
    run,
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    @connector.capability_registration_at(registry, 1).unwrap(),
    dispatch_test_generated(run),
    dispatch_test_limits(),
  ).unwrap()
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
  let old = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  @strategy.revise_strategy(
    run,
    search_offers(run, registry, [1, 2, 3], Some(1L)),
    registry,
    None,
  ).unwrap()
  |> ignore
  assert_true(@dbhost.execute_synchronous_dispatch(old) is Err(StaleTask))
  let replacement = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
  assert_true(
    physical_equal(
      @dbhost.dispatch_registration(replacement).unwrap(),
      @dbhost.dispatch_duckdb_registration(host),
    ),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  @dbhost.stop_strategy_dispatch(host)
  assert_true(@dbhost.take_native_dispatch(replacement) is Err(StaleTask))
}
