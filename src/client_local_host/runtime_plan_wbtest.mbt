///|
test "runtime consumes the original plan and refuses an equal foreign graph before provider construction" {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let prepared = single_source_free_capacity_prepared()
  let original = prepare_source_free_local_requirements(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  let foreign = prepare_source_free_local_requirements(
    single_source_free_capacity_prepared(),
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_false(physical_equal(original.capacity_plan, foreign.capacity_plan))
  // Equal authored inputs do not replace the checked graph or its plan.
  // A graph-less low-level quote is not a runtime configuration either.
  for
    plan in [
      foreign.capacity_plan,
      client_local_capacity_plan(
        original.sequences,
        original.capacity_plan.admitted_rows,
      ),
    ] {
    let ledger = @resources.create_ledger(original.maximum_limits()).unwrap()
    let run = @strategy.open_source_free_dag(graph, ledger).unwrap()
    let mut providers = 0
    assert_true(
      configure_client_local_run(
        run,
        graph,
        plan,
        0,
        @strategy.graph_task_count(graph),
        AdmittedRows,
        original.capacity.provider_retained,
        original.capacity.provider_execution,
        true,
        1L,
        0L,
        0L,
        0L,
        _ => {
          providers += 1
          []
        },
      )
      is None,
    )
    assert_eq(providers, 0)
    let usage = @resources.ledger_usage(ledger)
    assert_eq(usage.attempts, 0)
    assert_eq(usage.held_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
  }
  let ledger = @resources.create_ledger(original.maximum_limits()).unwrap()
  let run = @strategy.open_source_free_dag(graph, ledger).unwrap()
  let mut providers = 0
  let setup = configure_client_local_run(
    run,
    graph,
    original.capacity_plan,
    0,
    @strategy.graph_task_count(graph),
    AdmittedRows,
    original.capacity.provider_retained,
    original.capacity.provider_execution,
    true,
    1L,
    0L,
    0L,
    0L,
    _ => {
      providers += 1
      []
    },
  ).unwrap()
  assert_eq(providers, 1)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}", "{\"id\":2}"])
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_true(execution.close())
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.attempts, 1)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "nonretained Local entry keeps its original plan and valid Values execution" {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let setup = open_source_free_local_host(
    single_source_free_capacity_prepared(),
    contracts,
    assets.values,
    1L,
    0L,
    0L,
    0L,
    fragment_body=Some(assets.fragment),
    ordered_body=assets.ordered,
  ).unwrap()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let ledger = @strategy.captured_dag_ledger(run)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  let execution = execute_source_free_values(setup, 64, 100000).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}", "{\"id\":2}"])
  assert_true(execution.close())
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.attempts, 1)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}
