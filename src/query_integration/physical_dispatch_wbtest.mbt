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
    if @pipeline.step_count(@lower.pipeline(@lower.bound_preparation(owner))) ==
      1 {
      compute_test_sequence(owner)
    } else {
      query_generated(owner)
    }
  })
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
    assert_false(@dbhost.dispatch_is_native(prepared))
    assert_true(@dbhost.prepare_next_dispatch(host) is Err(PendingTask))
    @dbhost.execute_local_dispatch(prepared).unwrap()
    assert_true(@dbhost.execute_local_dispatch(prepared) is Err(StaleTask))
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
  assert_true(@dbhost.execute_local_dispatch(old) is Err(StaleTask))
  let replacement = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
  assert_true(@dbhost.dispatch_is_native(replacement))
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  @dbhost.stop_strategy_dispatch(host)
  assert_true(@dbhost.take_native_dispatch(replacement) is Err(StaleTask))
}
