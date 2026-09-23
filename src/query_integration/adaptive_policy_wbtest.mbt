///|
test "adaptive implementation failure is sticky and revokes old direct dispatch" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let driver = @host_driver.open_dispatch_driver(run)
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let calls = [0]
  let fail = [false]
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(
          _context : Unit,
          task,
          _quantities : @host_driver.TaskEstimateQuantities,
        ) -> Result[Array[@strategy.TaskOffer], String] {
          calls[0] += 1
          if fail[0] {
            return Err("provider-estimate-failed")
          }
          @strategy.prepare_task_offer(
            run,
            task,
            registration,
            1,
            [{ work_slots: [0], milliseconds: Some(1L), }],
            {
              transfer_bytes: 0L,
              retained_bytes: 100L,
              execution_bytes: 2000L,
            },
            100,
          )
          .map(offer => [offer])
          .map_err(_ => "offer-failed")
        },
      ),
    ],
    1,
  ).unwrap()
  let policy = @host_driver.open_adaptive_dispatch(
    driver,
    registry,
    entries,
    [Some(1000), Some(1000), Some(1000)],
    { max_offers: 3, max_strategies: 1, max_work: 1000, max_revisions: 2, },
    0,
  ).unwrap()
  @host_driver.refresh_adaptive_dispatch(policy).unwrap()
  assert_eq(calls[0], 3)
  @host_driver.refresh_adaptive_dispatch(policy).unwrap()
  assert_eq(calls[0], 3)
  // A real reservation changes the state and cannot be erased by reselection.
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 1L, 1L, 1L).unwrap()
  fail[0] = true
  assert_true(
    @host_driver.refresh_adaptive_dispatch(policy)
    is Err(Implementation("provider-estimate-failed")),
  )
  let stopped = @resources.ledger_usage(ledger)
  assert_true(@strategy.next_captured_task(run) is None)
  assert_eq(@strategy.strategy_history_count(run), 1)
  assert_eq(calls[0], 4)
  assert_true(
    @host_driver.refresh_adaptive_dispatch(policy)
    is Err(Implementation("provider-estimate-failed")),
  )
  assert_eq(calls[0], 4)
  assert_eq(@resources.ledger_usage(ledger), stopped)
  @resources.settle_reservation(ledger, reservation).unwrap()
}

///|
test "adaptive policy waits for an explicit feasible placement" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let driver = @host_driver.open_dispatch_driver(run)
  let local_registration = @connector.capability_registration_at(registry, 0).unwrap()
  let native = @connector.capability_registration_at(registry, 1).unwrap()
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        local_registration,
        fn(
          _context : Unit,
          task,
          _quantities : @host_driver.TaskEstimateQuantities,
        ) -> Result[Array[@strategy.TaskOffer], String] {
          @strategy.prepare_task_offer(
            run,
            task,
            local_registration,
            1,
            [{ work_slots: [0], milliseconds: Some(1L), }],
            {
              transfer_bytes: 0L,
              retained_bytes: 100L,
              execution_bytes: 2000L,
            },
            100,
          )
          .map(offer => [offer])
          .map_err(_ => "local-offer-failed")
        },
      ),
      (
        native,
        fn(
          _context : Unit,
          task,
          _quantities : @host_driver.TaskEstimateQuantities,
        ) -> Result[Array[@strategy.TaskOffer], String] {
          @strategy.prepare_task_offer(
            run,
            task,
            native,
            1,
            [{ work_slots: [0], milliseconds: Some(100L), }],
            {
              transfer_bytes: 0L,
              retained_bytes: 100L,
              execution_bytes: 2000L,
            },
            100,
          )
          .map(offer => [offer])
          .map_err(_ => "native-offer-failed")
        },
      ),
    ],
    2,
  ).unwrap()
  let policy = @host_driver.open_adaptive_dispatch(
    driver,
    registry,
    entries,
    [Some(1000), Some(1000), Some(1000)],
    { max_offers: 6, max_strategies: 8, max_work: 1000, max_revisions: 1, },
    0,
  ).unwrap()
  let choices = @host_driver.prepare_adaptive_policy_choice(policy)
    .unwrap()
    .unwrap()
  assert_eq(@strategy.strategy_choice_count(choices), 8)
  assert_eq(@strategy.strategy_history_count(run), 0)
  @host_driver.refresh_adaptive_dispatch(policy).unwrap()
  assert_true(@strategy.captured_dag_strategy(run) is None)
  assert_true(
    @host_driver.commit_adaptive_policy_choice(policy, Some(8))
    is Err(Search(InvalidPreference)),
  )
  assert_true(@strategy.captured_dag_strategy(run) is None)
  let request = @host_driver.prepare_adaptive_policy_request(
    policy, "plan-17", "run-17", "authority-1", 100L, 0L,
  ).unwrap()
  let candidates = @host_driver.adaptive_policy_candidates(policy).unwrap()
  assert_eq(candidates.cid, request.candidate_set_cid)
  let wire = "{\"authority\":\"authority-1\",\"candidate_set_cid\":\"" +
    request.candidate_set_cid +
    "\",\"deadline_ms\":\"100\",\"explanation\":\"prefer native\",\"generation\":0,\"policy_id\":\"cloud-placement\",\"policy_revision\":\"r2\",\"position\":7,\"request_id\":\"plan-17\",\"revision\":1,\"run_identity\":\"run-17\",\"version\":\"actql-placement-policy/0.1\"}"
  assert_true(
    @host_driver.commit_adaptive_policy_response_json(
      policy, request, wire, "untrusted-policy", 1L,
    )
    is Err(Search(InvalidPreference)),
  )
  assert_true(@strategy.captured_dag_strategy(run) is None)
  @host_driver.commit_adaptive_policy_response_json(
    policy, request, wire, "cloud-placement", 1L,
  ).unwrap()
  let revision = @strategy.captured_dag_strategy(run).unwrap()
  assert_eq(@strategy.strategy_assessment(revision).position, 7)
  assert_eq(
    @strategy.strategy_selection_source(revision),
    @strategy.ExternalPolicy({
      policy_id: "cloud-placement",
      revision: "r2",
      request_id: "plan-17",
      explanation: "prefer native",
    }),
  )
  assert_true(
    physical_equal(
      @strategy.strategy_registration(revision, 1).unwrap(),
      native,
    ),
  )
  assert_eq(@strategy.strategy_history_count(run), 1)
  assert_true(
    @host_driver.commit_adaptive_policy_choice(policy, Some(0))
    is Err(InvalidConfiguration),
  )
}
