///|
fn portfolio_profile(
  run : @strategy.CapturedDAG,
  binding : @connector.ResourceBinding,
  preparation : Int64,
  cleanup : Int64,
  import_ms : Int64,
) -> @strategy.ResidentProfile {
  let work = fn(milliseconds) {
    @strategy.prepare_shared_work(
      run,
      1,
      [{ work_slots: [0], milliseconds: Some(milliseconds), }],
      3,
    ).unwrap()
  }
  @strategy.prepare_resident_profile(
    run,
    binding,
    1000L,
    work(preparation),
    work(cleanup),
    Array::make(4, @strategy.ResidentImportEstimate::{
      work: work(import_ms),
      transfer_bytes: 20L,
      scratch_bytes: 100L,
      table_bytes: 80L,
    }),
  ).unwrap()
}

///|
fn portfolio_offers(
  run : @strategy.CapturedDAG,
  registry : @connector.CapabilityRegistry,
  profiles : Array[@strategy.ResidentProfile?],
) -> Array[@strategy.TaskOffer] {
  profiles.mapi((index, profile) => {
    let registration = match profile {
      Some(profile) => @strategy.resident_profile_registration(profile)
      None => @connector.capability_registration_at(registry, 0).unwrap()
    }
    let offer = @strategy.prepare_task_offer(
      run,
      index + 1,
      registration,
      1,
      [{ work_slots: [0], milliseconds: Some(1L), }],
      {
        transfer_bytes: if profile is Some(_) {
          100L
        } else {
          0L
        },
        retained_bytes: 100L,
        execution_bytes: 2000L,
      },
      100,
    ).unwrap()
    match profile {
      Some(profile) =>
        @strategy.resident_task_offer(run, offer, profile, 100L).unwrap()
      None => offer
    }
  })
}

///|
fn portfolio_select(
  run : @strategy.CapturedDAG,
  registry : @connector.CapabilityRegistry,
  profiles : Array[@strategy.ResidentProfile?],
) -> @strategy.StrategyAssessment {
  let offers = portfolio_offers(run, registry, profiles)
  @strategy.revise_strategy(run, offers, registry, None).unwrap() |> ignore
  @strategy.strategy_assessment(@strategy.captured_dag_strategy(run).unwrap())
}

///|
test "distinct bindings compose preparation imports retention and cleanup without false sharing" {
  for split in [false, true] {
    let (run, _) = captured_graph_fixture()
    let registry = search_registry()
    let registration = @connector.capability_registration_at(registry, 1).unwrap()
    let first = portfolio_profile(
      run,
      @connector.prepare_resource_binding(registry, registration).unwrap(),
      2L,
      7L,
      3L,
    )
    let second = portfolio_profile(
      run,
      @connector.prepare_resource_binding(registry, registration).unwrap(),
      5L,
      11L,
      13L,
    )
    @strategy.configure_strategy_search(run, {
      max_offers: 3,
      max_strategies: 1,
      max_work: 10000,
      max_revisions: 1,
    }).unwrap()
    let result = portfolio_select(run, registry, [
      Some(first),
      Some(if split { second } else { first }),
      Some(first),
    ])
    // Split: A/C use one X import and one environment, B uses another.
    // 3 tasks + (2+7+3) + (5+11+13) = 44, versus 3+(2+7+3)=15.
    let expected_duration = if split { 44L } else { 15L }
    assert_true(
      result.duration is Complete(value) && value == expected_duration,
    )
    assert_eq(result.transfer_bytes, if split { 340L } else { 320L })
    assert_eq(result.execution_bytes, if split { 3000L } else { 2000L })
    assert_eq(result.retained_bytes, 300L)
    assert_true(result.rejection is None)
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
      0,
    )
  }
}

///|
test "one binding cannot promise conflicting profiles in a strategy" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let registration = @connector.capability_registration_at(registry, 1).unwrap()
  let binding = @connector.prepare_resource_binding(registry, registration).unwrap()
  let first = portfolio_profile(run, binding, 2L, 7L, 3L)
  let conflicting = portfolio_profile(run, binding, 5L, 11L, 13L)
  @strategy.configure_strategy_search(run, {
    max_offers: 3,
    max_strategies: 1,
    max_work: 10000,
    max_revisions: 1,
  }).unwrap()
  let offers = portfolio_offers(run, registry, [
    Some(first),
    Some(conflicting),
    Some(first),
  ])
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None)
    is Err(InvalidCapacity),
  )
  assert_true(@strategy.captured_dag_strategy(run) is None)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.attempts, 0)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "two live bindings retain separate copies and cleanup costs after selecting Local" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let registration = @connector.capability_registration_at(registry, 1).unwrap()
  let profiles = [
    portfolio_profile(
      run,
      @connector.prepare_resource_binding(registry, registration).unwrap(),
      2L,
      7L,
      3L,
    ),
    portfolio_profile(
      run,
      @connector.prepare_resource_binding(registry, registration).unwrap(),
      5L,
      11L,
      13L,
    ),
  ]
  @strategy.configure_strategy_search(run, {
    max_offers: 3,
    max_strategies: 1,
    max_work: 10000,
    max_revisions: 6,
  }).unwrap()
  let environments = []
  let tables = []
  let stores = []
  let ledger = @strategy.captured_dag_ledger(run)
  for index, profile in profiles {
    portfolio_select(run, registry, Array::make(3, Some(profile))) |> ignore
    let env = @strategy.begin_resident_environment(run, 1, 1000L).unwrap()
    @strategy.confirm_resident_environment(run, env, 1000L).unwrap()
    // A second live intent for the same binding is never admitted.
    assert_true(
      @strategy.begin_resident_environment(run, 1, 1000L) is Err(NotReady),
    )
    let store = @duckdb_driver.prepare_resident_store(env)
    let table = @duckdb_driver.prepare_resident_table(
      run, store, 0, 80L, 1000, 10000, 10000,
    ).unwrap()
    let transfer = @strategy.begin_resident_transfer(run, table, 20L, 100L).unwrap()
    @strategy.charge_resident_transfer(run, transfer, 12L).unwrap()
    @strategy.settle_resident_transfer(run, transfer, true).unwrap()
    @strategy.complete_resident_transfer(run, transfer).unwrap()
    environments.push(env)
    tables.push(table)
    stores.push(store)
    assert_eq(
      @resources.ledger_usage(ledger).reserved_execution_bytes,
      (index + 1).to_int64() * 1000L,
    )
  }
  for env in environments {
    assert_true(@strategy.resident_environment_available(run, env))
  }
  assert_true(
    @duckdb_driver.resident_store_import(stores[0], tables[1]) is None,
  )
  assert_true(
    @duckdb_driver.resident_store_import(stores[1], tables[0]) is None,
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 24L)
  let local_profiles = [None, None, None]
  assert_true(
    portfolio_select(run, registry, local_profiles).duration is Complete(21L),
  )
  @strategy.close_resident_environment(run, environments[0]).unwrap()
  assert_true(@strategy.resident_environment_available(run, environments[1]))
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 2000L)
  assert_true(
    portfolio_select(run, registry, local_profiles).duration is Complete(21L),
  )
  @strategy.settle_resident_environment(run, environments[0]).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 1000L)
  assert_true(@strategy.resident_environment_available(run, environments[1]))
  assert_true(
    @duckdb_driver.resident_store_import(stores[1], tables[1]) is Some(_),
  )
  assert_true(
    portfolio_select(run, registry, local_profiles).duration is Complete(14L),
  )
  @strategy.close_resident_environment(run, environments[1]).unwrap()
  @strategy.settle_resident_environment(run, environments[1]).unwrap()
  assert_true(
    portfolio_select(run, registry, local_profiles).duration is Complete(3L),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 24L)
}
