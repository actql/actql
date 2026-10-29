///|
test "generated configuration rejects invalid registration sets before connector planning work" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let driver = @host_driver.open_dispatch_driver(run)
  let generated = dispatch_test_generated(run)
  let limits = dispatch_test_limits()
  let local_registration = @connector.capability_registration_at(registry, 0).unwrap()
  let native_registration = @connector.capability_registration_at(registry, 1).unwrap()
  let local_config : @local_driver.LocalComputeConfiguration = {
    sequences: generated,
    managed_providers: [],
    managed_capacity: limits.capacity,
    execution: limits.local_execution,
    measurement: limits.guards,
    max_work: limits.candidate_work,
  }
  let native_config : @duckdb_driver.DuckDBComputeConfiguration = {
    sequences: generated.map(@execution.generated_completion_preparation),
    limits: {
      capacity: limits.capacity,
      query: limits.native_query,
      join_validation: limits.join_validation,
      candidate_work: limits.candidate_work,
      execution: limits.native,
      transport: limits.transport,
    },
  }
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  for
    (registration, maximum) in [
      (local_registration, 1),
      (native_registration, 2),
      (@connector.capability_registration_at(search_registry(), 0).unwrap(), 2),
    ] {
    let result : Result[@builtin.ConfiguredComputeModules[String], String] = @builtin.configure_compute_modules(
      driver,
      registry,
      maximum,
      _ => "registration-set",
      with_local=Some(
        (registration, local_config, _ => "local", _ => "local-estimate"),
      ),
      with_duckdb=Some(
        (
          native_registration,
          native_config,
          _ => "native",
          _ => "native-estimate",
        ),
      ),
    )
    assert_true(result is Err("registration-set"))
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
      before,
    )
  }
  let configured = @builtin.configure_compute_modules(
    driver,
    registry,
    2,
    _ => "registration-set",
    with_local=Some(
      (local_registration, local_config, _ => "local", _ => "local-estimate"),
    ),
    with_duckdb=Some(
      (
        native_registration,
        native_config,
        _ => "native",
        _ => "native-estimate",
      ),
    ),
  ).unwrap()
  assert_true(@builtin.configured_reference_compute_module(configured) is None)
  assert_true(
    physical_equal(
      @local_driver.local_dispatch_registration(
        @builtin.configured_local_module(configured).unwrap(),
      ),
      local_registration,
    ),
  )
  assert_true(
    physical_equal(
      @duckdb_driver.duckdb_dispatch_registration(
        @builtin.configured_duckdb_module(configured).unwrap(),
      ),
      native_registration,
    ),
  )
  assert_true(
    physical_equal(
      @connector.capability_implementations_registry(
        @builtin.configured_compute_contributions(configured),
      ),
      registry,
    ),
  )
  let after = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.transferred_bytes, before.transferred_bytes)
  assert_true(after.planning_work > before.planning_work)
  let schedules = connector_test_schedules(
    @builtin.local_estimate_work_slots(),
    10L,
  )
  let settings : @local_driver.LocalEstimateSettings = {
    schedules,
    eligible: [],
    max_work: 100,
  }
  let absent : @builtin.ConfiguredComputeModules[String] = @builtin.configure_compute_modules(
    driver,
    registry,
    0,
    _ => "registration-set",
  ).unwrap()
  assert_true(
    @builtin.prepare_local_estimate_policy(absent, settings)
    is Err(MissingImplementation),
  )
  let policy = @builtin.prepare_local_estimate_policy(configured, settings).unwrap()
  schedules.clear()
  @builtin.install_configured_estimate_policy(policy).unwrap()
  assert_true(
    @builtin.install_configured_estimate_policy(policy) is Err("local-estimate"),
  )
  let profile = portfolio_profile(
    run,
    @connector.prepare_resource_binding(registry, native_registration).unwrap(),
    1L,
    1L,
    1L,
  )
  let resource_schedules = connector_test_schedules(
    @builtin.duckdb_resource_work_slots(),
    1L,
  )
  let resource_policy = @builtin.prepare_duckdb_resource_policy(configured, {
    profile,
    schedules: resource_schedules,
  }).unwrap()
  resource_schedules.clear()
  @builtin.install_configured_estimate_policy(resource_policy).unwrap()
  assert_true(
    @builtin.install_configured_estimate_policy(resource_policy)
    is Err("native-estimate"),
  )
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    before.attempts,
  )
  @connector.close_capability_registry(registry)
  let closed : Result[@builtin.ConfiguredComputeModules[String], String] = @builtin.configure_compute_modules(
    driver,
    registry,
    0,
    _ => "closed",
  )
  assert_true(closed is Err("closed"))
}

///|
test "generated prepared assembly retains original modules across Local numeric and mixed subsets" {
  let (run, issuer) = captured_graph_fixture()
  let registry = search_registry()
  let driver = @host_driver.open_dispatch_driver(run)
  let generated = dispatch_test_generated(run)
  let limits = dispatch_test_limits()
  let original = @local_driver.prepare_local_dispatch_plan(
    @strategy.captured_dag_graph(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    generated,
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  let local_module = @local_driver.bind_local_dispatch_plan(driver, original).unwrap()
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100,
    max_bytes: 100,
    max_nodes: 100,
    max_depth: 10,
  }
  let numeric = @reference_driver.configure_numeric_compute(
    driver,
    registry,
    @connector.capability_registration_at(registry, 1).unwrap(),
    {
      sequences: generated.map(@execution.generated_completion_preparation),
      limits: {
        max_work: 100,
        max_entries: 100,
        max_name_bytes: 10000,
        values: {
          max_nodes: 100,
          max_text_bytes: 100,
          max_depth: 10,
          max_work: 100,
        },
        physical: measurement,
        roots: measurement,
      },
      expressions: limits.native_query.expressions,
      milliseconds: Some(1L),
      max_work: 100,
    },
  ).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  let before = @resources.ledger_usage(ledger)
  for mode in [0, 1, 2] {
    let configured = @builtin.assemble_configured_compute_modules(
      driver,
      registry,
      2,
      _ => "registration-set",
      with_local=if mode != 1 {
        Some((local_module, _ => "local-binding", _ => "local-estimate"))
      } else {
        None
      },
      with_reference_compute=if mode != 0 {
        Some((numeric, _ => "numeric-binding", _ => "numeric-estimate"))
      } else {
        None
      },
    ).unwrap()
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_eq(
      @builtin.configured_compute_module_keys(configured),
      match mode {
        0 => ["local"]
        1 => ["reference_compute"]
        _ => ["local", "reference_compute"]
      },
    )
    if mode != 1 {
      let selected = @builtin.configured_local_module(configured).unwrap()
      assert_true(physical_equal(selected, local_module))
      assert_true(
        physical_equal(
          @local_driver.local_dispatch_original_preparation(selected).unwrap(),
          original,
        ),
      )
    }
    if mode != 0 {
      assert_true(
        physical_equal(
          @builtin.configured_reference_compute_module(configured).unwrap(),
          numeric,
        ),
      )
    }
    let host = @builtin.open_configured_compute_host(
      configured,
      registry,
      limits.capacity,
      100,
      10000,
      2,
    ).unwrap()
    assert_true(physical_equal(@builtin.configured_host_driver(host), driver))
  }
  // The Run alone cannot stand in for its exact driver/channel binding.
  let other_driver = @host_driver.open_dispatch_driver(run)
  for candidate in [other_driver, driver] {
    let selected_registry = if physical_equal(candidate, driver) {
      search_registry()
    } else {
      registry
    }
    assert_true(
      @builtin.assemble_configured_compute_modules(
        candidate,
        selected_registry,
        2,
        _ => "registration-set",
        with_local=Some(
          (local_module, _ => "local-binding", _ => "local-estimate"),
        ),
      )
      is Err("local-binding"),
    )
  }
  assert_true(
    @builtin.assemble_configured_compute_modules(
      other_driver,
      registry,
      2,
      _ => "registration-set",
      with_reference_compute=Some(
        (numeric, _ => "numeric-binding", _ => "numeric-estimate"),
      ),
    )
    is Err("numeric-binding"),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
  @strategy.refresh_captured_retention(run)
}
