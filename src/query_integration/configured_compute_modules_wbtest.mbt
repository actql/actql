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
