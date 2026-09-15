///|
fn connector_test_schedules(
  slots : Int,
  milliseconds : Int64,
) -> Array[@cost.RateSchedule] {
  let schedule = @cost.prepare_rate_schedule(
    slots,
    [
      {
        work_slots: Array::makei(slots, index => index),
        fixed_ms: Some(milliseconds),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    100,
  ).unwrap()
  Array::make(3, schedule)
}

///|
test "connector estimate modules own schedules without Host policy state or caller arrays" {
  for use_duckdb in [false, true] {
    let (run, _) = captured_graph_fixture()
    let registry = search_registry()
    let driver = @host_driver.open_dispatch_driver(run)
    let registration = @connector.capability_registration_at(
      registry,
      if use_duckdb {
        1
      } else {
        0
      },
    ).unwrap()
    let generated = dispatch_test_generated(run)
    let quantities : @host_driver.TaskEstimateQuantities = {
      rows: None,
      wire_bytes: None,
      pairs: None,
    }
    let offers = if use_duckdb {
      let installed = @duckdb_driver.prepare_duckdb_dispatch_module(
        driver,
        registry,
        registration,
        generated.map(@execution.generated_completion_preparation),
        duckdb_dispatch_module_limits(),
      ).unwrap()
      let schedules = connector_test_schedules(
        @duckdb_driver.duckdb_dispatch_work_slots(),
        19L,
      )
      let capacities = Array::make(3, @strategy.PhysicalEnvelope::{
        transfer_bytes: 100L,
        retained_bytes: 100L,
        execution_bytes: 2000L,
      })
      assert_true(
        @duckdb_driver.prepare_duckdb_estimate_module(
          installed, schedules, capacities, 2,
        )
        is Err(InvalidConfiguration),
      )
      let policy = @duckdb_driver.prepare_duckdb_estimate_module(
        installed, schedules, capacities, 1000,
      ).unwrap()
      assert_true(
        @duckdb_driver.estimate_duckdb_installed_offers(
          installed, 1, quantities,
        )
        is Err(InvalidConfiguration),
      )
      @duckdb_driver.install_duckdb_dispatch_estimates(installed, policy).unwrap()
      assert_true(
        @duckdb_driver.install_duckdb_dispatch_estimates(installed, policy)
        is Err(InvalidConfiguration),
      )
      assert_eq(
        @duckdb_driver.estimate_duckdb_installed_offers(
          installed, 1, quantities,
        )
        .unwrap()
        .length(),
        1,
      )
      schedules.clear()
      capacities.clear()
      assert_true(
        @duckdb_driver.estimate_duckdb_module_offers(policy, 0, quantities)
        is Err(InvalidConfiguration),
      )
      Array::makei(3, index => {
        @duckdb_driver.estimate_duckdb_module_offers(
          policy,
          index + 1,
          quantities,
        ).unwrap()[0]
      })
    } else {
      let limits = dispatch_test_limits()
      let installed = @local_driver.prepare_local_dispatch_module(
        driver,
        registry,
        registration,
        generated,
        limits.local_execution,
        limits.guards,
        1000,
      ).unwrap()
      let schedules = connector_test_schedules(
        @local_driver.local_dispatch_work_slots(),
        11L,
      )
      assert_true(
        @local_driver.prepare_local_estimate_module(installed, schedules, 2)
        is Err(InvalidConfiguration),
      )
      let policy = @local_driver.prepare_local_estimate_module(
        installed, schedules, 1000,
      ).unwrap()
      assert_true(
        @local_driver.estimate_local_installed_offers(installed, 1, quantities)
        is Err(InvalidConfiguration),
      )
      @local_driver.install_local_dispatch_estimates(installed, policy).unwrap()
      assert_true(
        @local_driver.install_local_dispatch_estimates(installed, policy)
        is Err(InvalidConfiguration),
      )
      assert_eq(
        @local_driver.estimate_local_installed_offers(installed, 1, quantities)
        .unwrap()
        .length(),
        1,
      )
      schedules.clear()
      assert_true(
        @local_driver.estimate_local_module_offers(policy, 4, quantities)
        is Err(InvalidConfiguration),
      )
      Array::makei(3, index => {
        @local_driver.estimate_local_module_offers(
          policy,
          index + 1,
          quantities,
        ).unwrap()[0]
      })
    }
    for index, offer in offers {
      assert_true(
        @strategy.task_offer_matches(run, index + 1, registration, offer),
      )
    }
    @strategy.configure_strategy_search(run, {
      max_offers: 3,
      max_strategies: 1,
      max_work: 10000,
      max_revisions: 1,
    }).unwrap()
    @strategy.revise_strategy(run, offers, registry, None).unwrap() |> ignore
    let assessment = @strategy.strategy_assessment(
      @strategy.captured_dag_strategy(run).unwrap(),
    )
    let expected = if use_duckdb { 57L } else { 33L }
    assert_true(assessment.duration is Complete(value) && value == expected)
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
      0,
    )
  }
}

///|
test "resident estimate installation is owned by the exact connector and run" {
  let (run, _) = captured_graph_fixture()
  let (other_run, _) = captured_graph_fixture()
  let registry = search_registry()
  let registration = @connector.capability_registration_at(registry, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let installed = @duckdb_driver.prepare_duckdb_dispatch_module(
    driver,
    registry,
    registration,
    dispatch_test_generated(run).map(
      @execution.generated_completion_preparation,
    ),
    duckdb_dispatch_module_limits(),
  ).unwrap()
  let other = @duckdb_driver.prepare_duckdb_dispatch_module(
    driver,
    registry,
    registration,
    dispatch_test_generated(run).map(
      @execution.generated_completion_preparation,
    ),
    duckdb_dispatch_module_limits(),
  ).unwrap()
  let binding = @connector.prepare_resource_binding(registry, registration).unwrap()
  let foreign_profile = portfolio_profile(other_run, binding, 1L, 1L, 1L)
  let profile = portfolio_profile(run, binding, 1L, 1L, 1L)
  let schedules = connector_test_schedules(
    @duckdb_driver.duckdb_dispatch_work_slots(),
    1L,
  )
  assert_true(
    @duckdb_driver.install_duckdb_resident_estimates(
      installed, foreign_profile, schedules,
    )
    is Err(InvalidConfiguration),
  )
  @duckdb_driver.install_duckdb_resident_estimates(
    installed, profile, schedules,
  ).unwrap()
  assert_true(
    @duckdb_driver.install_duckdb_resident_estimates(
      installed, profile, schedules,
    )
    is Err(InvalidConfiguration),
  )
  schedules.clear()
  assert_true(@duckdb_driver.duckdb_resident_estimates_installed(installed))
  assert_false(@duckdb_driver.duckdb_resident_estimates_installed(other))
  let second_binding = @connector.prepare_resource_binding(
    registry, registration,
  ).unwrap()
  let second_profile = portfolio_profile(run, second_binding, 2L, 2L, 2L)
  @duckdb_driver.install_duckdb_resident_estimates(
    installed,
    second_profile,
    connector_test_schedules(@duckdb_driver.duckdb_dispatch_work_slots(), 2L),
  ).unwrap()
  // A different profile cannot replace the same owned resource's configuration.
  assert_true(
    @duckdb_driver.install_duckdb_resident_estimates(
      installed,
      portfolio_profile(run, second_binding, 3L, 3L, 3L),
      connector_test_schedules(@duckdb_driver.duckdb_dispatch_work_slots(), 3L),
    )
    is Err(InvalidConfiguration),
  )
  let capacities = Array::make(3, @strategy.PhysicalEnvelope::{
    transfer_bytes: 100L,
    retained_bytes: 100L,
    execution_bytes: 2000L,
  })
  let policy = @duckdb_driver.prepare_duckdb_estimate_module(
    installed,
    connector_test_schedules(@duckdb_driver.duckdb_dispatch_work_slots(), 10L),
    capacities,
    1000,
  ).unwrap()
  assert_true(
    @duckdb_driver.install_duckdb_dispatch_estimates(other, policy)
    is Err(InvalidConfiguration),
  )
  let offers = @duckdb_driver.estimate_duckdb_module_offers(policy, 1, {
    rows: None,
    wire_bytes: None,
    pairs: None,
  }).unwrap()
  assert_eq(offers.length(), 3)
  for offer in offers {
    assert_true(@strategy.task_offer_matches(run, 1, registration, offer))
  }
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
}
