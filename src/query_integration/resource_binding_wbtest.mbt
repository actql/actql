///|
fn binding_profile(
  run : @strategy.CapturedDAG,
  binding : @connector.ResourceBinding,
) -> @strategy.ResidentProfile {
  let work = @strategy.prepare_shared_work(run, 0, [], 0).unwrap()
  @strategy.prepare_resident_profile(
    run,
    binding,
    1000L,
    work,
    work,
    Array::make(4, @strategy.ResidentImportEstimate::{
      work,
      transfer_bytes: 20L,
      scratch_bytes: 100L,
      table_bytes: 80L,
    }),
  ).unwrap()
}

///|
fn select_binding_profile(
  run : @strategy.CapturedDAG,
  registry : @connector.CapabilityRegistry,
  profile : @strategy.ResidentProfile,
) -> Unit {
  let offers = [1, 2, 3].map(task => {
    let base = @strategy.prepare_task_offer(
      run,
      task,
      @strategy.resident_profile_registration(profile),
      1,
      [{ work_slots: [0], milliseconds: Some(1L), }],
      { transfer_bytes: 100L, retained_bytes: 100L, execution_bytes: 2000L, },
      100,
    ).unwrap()
    @strategy.resident_task_offer(run, base, profile, 100L).unwrap()
  })
  @strategy.revise_strategy(run, offers, registry, None).unwrap() |> ignore
}

///|
test "successive bindings of one implementation retain distinct resource and copy ownership" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let implementation = @connector.capability_registration_at(registry, 1).unwrap()
  let first = @connector.prepare_resource_binding(registry, implementation).unwrap()
  let second = @connector.prepare_resource_binding(registry, implementation).unwrap()
  let profiles = [binding_profile(run, first), binding_profile(run, second)]
  @strategy.configure_strategy_search(run, {
    max_offers: 3,
    max_strategies: 1,
    max_work: 10000,
    max_revisions: 2,
  }).unwrap()
  let mut old_table : @strategy.ResidentTable? = None
  for index, profile in profiles {
    assert_true(
      physical_equal(
        @strategy.resident_profile_registration(profile),
        implementation,
      ),
    )
    select_binding_profile(run, registry, profile)
    let env = @strategy.begin_resident_environment(run, 1, 1000L).unwrap()
    assert_true(
      physical_equal(
        @strategy.resident_environment_resource_binding(env).unwrap(),
        if index == 0 {
          first
        } else {
          second
        },
      ),
    )
    assert_false(@strategy.resident_environment_available(run, env))
    @strategy.confirm_resident_environment(run, env, 1000L).unwrap()
    let store = @duckdb_driver.prepare_resident_store(env)
    if old_table is Some(previous) {
      assert_true(@duckdb_driver.resident_store_import(store, previous) is None)
      assert_true(
        @duckdb_driver.borrow_resident_table(
          run, store, previous, 1, 1000, 10000, 10000,
        )
        is Err(_),
      )
    }
    let table = @duckdb_driver.prepare_resident_table(
      run, store, 0, 80L, 1000, 10000, 10000,
    ).unwrap()
    let transfer = @strategy.begin_resident_transfer(run, table, 20L, 100L).unwrap()
    @strategy.charge_resident_transfer(run, transfer, 12L).unwrap()
    @strategy.settle_resident_transfer(run, transfer, true).unwrap()
    @strategy.complete_resident_transfer(run, transfer).unwrap()
    old_table = Some(table)
    @strategy.close_resident_environment(run, env).unwrap()
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
      1000L,
    )
    @strategy.settle_resident_environment(run, env).unwrap()
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.transferred_bytes, (index + 1).to_int64() * 12L)
  }
}

///|
test "closed implementation rejects new resource provision and pending confirmation without losing cleanup" {
  for began in [false, true] {
    let (run, _) = captured_graph_fixture()
    let registry = search_registry()
    let binding = @connector.prepare_resource_binding(
      registry,
      @connector.capability_registration_at(registry, 1).unwrap(),
    ).unwrap()
    let profile = binding_profile(run, binding)
    @strategy.configure_strategy_search(run, {
      max_offers: 3,
      max_strategies: 1,
      max_work: 10000,
      max_revisions: 1,
    }).unwrap()
    select_binding_profile(run, registry, profile)
    let env = if began {
      Some(@strategy.begin_resident_environment(run, 1, 1000L).unwrap())
    } else {
      None
    }
    @connector.close_capability_registry(registry)
    if env is Some(env) {
      assert_true(
        @strategy.confirm_resident_environment(run, env, 1000L)
        is Err(ForeignCandidate),
      )
      assert_eq(
        @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
        1000L,
      )
      @strategy.close_resident_environment(run, env).unwrap()
      @strategy.settle_resident_environment(run, env).unwrap()
    } else {
      assert_true(
        @strategy.begin_resident_environment(run, 1, 1000L)
        is Err(ForeignCandidate),
      )
      assert_eq(
        @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
        0,
      )
    }
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
      0L,
    )
  }
}
