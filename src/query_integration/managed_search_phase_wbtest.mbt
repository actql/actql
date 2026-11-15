///|
// Real checked Effect/managed preparation and Search owners from the existing
// in-memory component fixture. No physical installation or authorization is
// supplied by this test. Each search uses original registration handles.
test "managed candidates distinguish configured limits from pending and selected placement" {
  for state in 0..<6 {
    let (bound, captured, contracts, values, fragment) = local_effect_dispatch_fixture()
    let run = @strategy.captured_effect_run_dag(captured)
    let host = @client_local_host.configure_source_free_effect_local_retained_host(
      bound,
      captured,
      contracts,
      values,
      fragment,
      None,
    ).unwrap()
    let installed = @builtin.configured_local_module(
      @builtin.configured_host_modules(host),
    ).unwrap()
    @strategy.configure_strategy_search(run, {
      max_offers: 100,
      max_strategies: 100,
      max_work: 10000,
      max_revisions: 1,
    }).unwrap()
    let candidate = @local_driver.prepare_local_managed_dispatch(
        installed,
        [],
        @execution.process_managed_obligations(
          @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 0).unwrap(),
        ),
        0L,
      )
      .unwrap()
      .unwrap()
    // Opening another registry with the same spelling cannot replace the
    // installed registration. The selected entry remains a nominal original.
    let foreign = search_registry()
    if state > 0 {
      let registration = @connector.capability_registration_at(
        foreign,
        if state == 4 {
          0
        } else {
          1
        },
      ).unwrap()
      let offer = @strategy.prepare_task_offer(
        run,
        0,
        registration,
        1,
        [{ work_slots: [0], milliseconds: Some(1L), }],
        {
          transfer_bytes: 0L,
          retained_bytes: if state == 3 {
            @resources.ledger_limits(@strategy.captured_dag_ledger(run)).retained_bytes +
            1L
          } else {
            0L
          },
          execution_bytes: 0L,
        },
        100,
      ).unwrap()
      let choices = @strategy.prepare_strategy_choices(
        run,
        [offer],
        foreign,
        None,
      ).unwrap()
      if state == 2 || state == 4 {
        assert_true(
          @strategy.commit_strategy_choice(choices, Some(0)) is Ok(Selected(_)),
        )
      } else if state == 3 {
        assert_eq(@strategy.strategy_choice_count(choices), 0)
        assert_true(
          @strategy.commit_strategy_choice(choices, None) is Ok(NoFeasible),
        )
      } else if state == 5 {
        let ledger = @strategy.captured_dag_ledger(run)
        let occupied = @resources.reserve_capacity(ledger, 0L, 1L).unwrap()
        assert_true(
          @strategy.commit_strategy_choice(choices, Some(0)) is Err(StaleChoice),
        )
        @resources.settle_capacity(ledger, occupied).unwrap()
      }
    }
    let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    if state == 0 {
      // Merely configured fallback limits do not select a legacy candidate.
      // The real nominal managed candidate still owns all admission checks.
      let operations = @local_driver.start_local_managed_dispatch_node(
        candidate,
      ).unwrap()
      assert_true((operations.request_cancel)())
      assert_true((operations.advance)(1) is Err(_))
      assert_true((operations.execution_stopped)())
      (operations.settle)().unwrap()
      (operations.close)()
      (operations.cleanup_refresh)() |> ignore
    } else {
      assert_true(
        @local_driver.start_local_managed_dispatch_node(candidate)
        is Err(Execution(ForeignCandidate)),
      )
      assert_eq(
        @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
        before,
      )
      assert_false(@strategy.captured_task_completed(run, 0))
    }
    local_effect_dispatch_stop(captured)
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.held_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
    @connector.close_capability_registry(foreign)
  }
}

///|
test "configured managed candidates retain registry currentness and reject reconfiguration" {
  let (bound, captured, contracts, values, fragment) = local_effect_dispatch_fixture()
  let run = @strategy.captured_effect_run_dag(captured)
  let sequences = @client_local_host.prepare_client_effect_local_sequences(
    @publication_host.prepared_client_effect_run_computation(bound),
    contracts,
    values,
    fragment,
    None,
  ).unwrap()
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    sequences,
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  configure_local_managed_test_inputs(
    installed,
    @client_local_host.client_local_import_limits(
      limits.capacity,
      limits.local_execution.rows.input_values,
    ),
    limits,
  )
  @strategy.configure_strategy_search(run, {
    max_offers: 100,
    max_strategies: 100,
    max_work: 10000,
    max_revisions: 1,
  }).unwrap()
  let candidate = @local_driver.prepare_local_managed_dispatch(
      installed,
      [],
      @execution.process_managed_obligations(
        @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 0).unwrap(),
      ),
      0L,
    )
    .unwrap()
    .unwrap()
  assert_true(
    @strategy.configure_strategy_search(run, {
      max_offers: 100,
      max_strategies: 100,
      max_work: 10000,
      max_revisions: 1,
    })
    is Err(AlreadyConfigured),
  )
  // The real parent registration can become unavailable after preparation.
  // Configured-only search never makes that stale candidate current again.
  @connector.close_capability_registry(registry)
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(
    @local_driver.start_local_managed_dispatch_node(candidate)
    is Err(Configuration(NotSelected)),
  )
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), before)
  assert_false(@strategy.captured_task_completed(run, 0))
  local_effect_dispatch_stop(captured)
}
