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
  registry : @connector.CapabilityRegistry,
) -> @dbhost.StrategyHostDispatch raise {
  @dbhost.configure_strategy_dispatch(
    run,
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    @connector.capability_registration_at(registry, 1).unwrap(),
    dispatch_test_generated(run),
    dispatch_test_limits(),
  ).unwrap()
}

///|
test "standard Host commits an authenticated external policy before dispatch" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let host = adaptive_host(run, registry)
  @dbhost.configure_dispatch_estimates(host, adaptive_profiles(), {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 2,
  }).unwrap()
  assert_true(@dbhost.prepare_dispatch_policy_choice(host).unwrap())
  assert_true(@dbhost.prepare_next_dispatch(host) is Err(NoStrategy))
  let request = @dbhost.prepare_dispatch_policy_request(
    host, "request-1", "run-1", "authority-1", 100L, 0L,
  ).unwrap()
  let candidates = @dbhost.dispatch_policy_candidates(host).unwrap()
  assert_eq(candidates.cid, request.candidate_set_cid)
  assert_true(!candidates.canonical_json.is_empty())
  let wire = "{\"authority\":\"authority-1\",\"candidate_set_cid\":\"" +
    request.candidate_set_cid +
    "\",\"deadline_ms\":\"100\",\"explanation\":\"configured placement\",\"generation\":" +
    request.generation.to_string() +
    ",\"policy_id\":\"placement-service\",\"policy_revision\":\"r1\",\"position\":0,\"request_id\":\"request-1\",\"revision\":" +
    request.revision.to_string() +
    ",\"run_identity\":\"run-1\",\"version\":\"actql-placement-policy/0.1\"}"
  assert_true(
    @dbhost.commit_dispatch_policy_response_json(
      host, request, wire, "other-service", 1L,
    )
    is Err(Search(InvalidPreference)),
  )
  assert_true(@strategy.captured_dag_strategy(run) is None)
  @dbhost.commit_dispatch_policy_response_json(
    host, request, wire, "placement-service", 1L,
  ).unwrap()
  assert_true(@strategy.captured_dag_strategy(run) is Some(_))
  assert_true(
    @dbhost.commit_dispatch_policy_response_json(
      host, request, wire, "placement-service", 2L,
    )
    is Err(_),
  )
  let prepared = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
  assert_eq(@dbhost.dispatch_task(prepared), 1)
}

///|
test "native standard Host consults mTLS policy and retains a failed choice" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(http_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_POLICY_CLOCK") is Some(clock_path) else {
    return
  }
  let http = @native_http.load_library(http_path).unwrap()
  let client = http.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @native_sqlite.load_library(sqlite_path).unwrap()
  let clock = @native_clock.open(
    sqlite, clock_path, "placement-policy-test", "coordinator",
  ).unwrap()
  let (run, _) = captured_graph_fixture()
  let host = adaptive_host(run, search_registry())
  @dbhost.configure_dispatch_estimates(host, adaptive_profiles(), {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 2,
  }).unwrap()
  let now = clock.observe().unwrap()
  let consultation = @native_host.prepare_native_standard_policy_consultation(
      host,
      client,
      clock,
      origin + "/placement-policy/choose",
      "configured-policy",
      "native-policy-request",
      "native-policy-run",
      "native-coordinator",
      now + 5000L,
      65536,
      (_, _) => true,
    )
    .unwrap()
    .unwrap()
  assert_true(@dbhost.prepare_next_dispatch(host) is Err(NoStrategy))
  @native_host.consult_native_standard_policy(consultation).unwrap()
  assert_true(
    @native_host.consult_native_standard_policy(consultation)
    is Err(@native_host.AlreadyCommitted),
  )
  assert_eq(
    @dbhost.dispatch_task(@dbhost.prepare_next_dispatch(host).unwrap().unwrap()),
    1,
  )
  let (retry_run, _) = captured_graph_fixture()
  let retry_host = adaptive_host(retry_run, search_registry())
  @dbhost.configure_dispatch_estimates(retry_host, adaptive_profiles(), {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 2,
  }).unwrap()
  let retry = @native_host.prepare_native_standard_policy_consultation(
      retry_host,
      client,
      clock,
      origin + "/placement-policy/flaky",
      "configured-policy",
      "native-retry-request",
      "native-retry-run",
      "native-coordinator",
      clock.observe().unwrap() + 5000L,
      65536,
      (_, _) => true,
    )
    .unwrap()
    .unwrap()
  assert_true(
    @native_host.consult_native_standard_policy(retry)
    is Err(@native_host.Transport(_)),
  )
  assert_true(@dbhost.prepare_next_dispatch(retry_host) is Err(NoStrategy))
  @native_host.consult_native_standard_policy(retry).unwrap()
  assert_eq(
    @dbhost.dispatch_task(
      @dbhost.prepare_next_dispatch(retry_host).unwrap().unwrap(),
    ),
    1,
  )
  let routes = [
    "/disconnect", "/placement-policy/foreign", "/placement-policy/late",
  ]
  for index = 0; index < routes.length(); index = index + 1 {
    let route = routes[index]
    let (other_run, _) = captured_graph_fixture()
    let other = adaptive_host(other_run, search_registry())
    @dbhost.configure_dispatch_estimates(other, adaptive_profiles(), {
      max_offers: 6,
      max_strategies: 8,
      max_work: 1000,
      max_revisions: 2,
    }).unwrap()
    let duration = if index == 2 { 100L } else { 5000L }
    let consultation = @native_host.prepare_native_standard_policy_consultation(
        other,
        client,
        clock,
        origin + route,
        "configured-policy",
        "native-failure-" + index.to_string(),
        "native-failure-run-" + index.to_string(),
        "native-coordinator",
        clock.observe().unwrap() + duration,
        65536,
        (_, _) => true,
      )
      .unwrap()
      .unwrap()
    assert_true(
      @native_host.consult_native_standard_policy(consultation) is Err(_),
    )
    assert_true(@dbhost.prepare_next_dispatch(other) is Err(NoStrategy))
    assert_true(@strategy.captured_dag_strategy(other_run) is None)
  }
  let (denied_run, _) = captured_graph_fixture()
  let denied_host = adaptive_host(denied_run, search_registry())
  @dbhost.configure_dispatch_estimates(denied_host, adaptive_profiles(), {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 2,
  }).unwrap()
  let denied = @native_host.prepare_native_standard_policy_consultation(
      denied_host,
      client,
      clock,
      origin + "/placement-policy/choose",
      "configured-policy",
      "native-denied-request",
      "native-denied-run",
      "native-coordinator",
      clock.observe().unwrap() + 5000L,
      65536,
      (_, _) => false,
    )
    .unwrap()
    .unwrap()
  assert_true(
    @native_host.consult_native_standard_policy(denied)
    is Err(@native_host.DisclosureDenied),
  )
  assert_true(@dbhost.prepare_next_dispatch(denied_host) is Err(NoStrategy))
  assert_true(clock.close())
  assert_true(client.close())
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
  let native_reg = @connector.capability_registration_at(registry, 1).unwrap()
  let local_reg = @connector.capability_registration_at(registry, 0).unwrap()
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
  @dbhost.execute_synchronous_dispatch(a).unwrap()
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
  @dbhost.execute_synchronous_dispatch(b).unwrap()
  let c = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
  assert_true(
    physical_equal(
      @dbhost.dispatch_registration(c).unwrap(),
      @dbhost.dispatch_local_registration(host),
    ),
  )
  @dbhost.execute_synchronous_dispatch(c).unwrap()
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
      @dbhost.execute_synchronous_dispatch(first).unwrap()
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
