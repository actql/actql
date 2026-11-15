///|
test "source-free fallback planning has no invented root statistics and stays lazy" {
  let prepared = source_free_tasks_original_union()
  let graph = @publication_host.prepared_client_graph(prepared)
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = prepare_source_free_local_requirements(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let ledger = @resources.create_ledger(original.maximum_limits()).unwrap()
  let run = @strategy.open_source_free_dag(graph, ledger).unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let observed : Array[(Int, Int64?, Int64?)] = []
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(
          _context : Unit,
          task,
          quantities : @host_driver.TaskEstimateQuantities,
        ) -> Result[Array[@strategy.TaskOffer], String] {
          observed.push((task, quantities.rows, quantities.wire_bytes))
          @strategy.prepare_task_offer(
            run,
            task,
            registration,
            1,
            [{ work_slots: [0], milliseconds: Some(1L), }],
            { transfer_bytes: 0L, retained_bytes: 0L, execution_bytes: 0L, },
            1000,
          )
          .map(offer => [offer])
          .map_err(_ => "offer-failed")
        },
      ),
    ],
    1,
  ).unwrap()
  let count = @strategy.graph_task_count(graph)
  let policy = @host_driver.open_adaptive_dispatch(
    @host_driver.open_dispatch_driver(run),
    registry,
    entries,
    Array::make(count, Some(1000)),
    { max_offers: count, max_strategies: 1, max_work: 1000, max_revisions: 2, },
    0,
  ).unwrap()
  assert_eq(observed.length(), 0)
  assert_true(@strategy.captured_dag_strategy(run) is None)
  assert_eq(@strategy.strategy_history_count(run), 0)
  let choices = @host_driver.prepare_adaptive_policy_choice(policy)
    .unwrap()
    .unwrap()
  assert_eq(@strategy.strategy_choice_count(choices), 1)
  assert_eq(observed.length(), count)
  assert_eq(observed[0], (0, Some(0L), Some(0L)))
  // The intrinsic Values output is not inferred as zero from its empty input.
  // Until it actually completes, its consumer's quantities remain unknown.
  assert_eq(observed[1], (1, None, None))
  @host_driver.refresh_adaptive_dispatch(policy).unwrap()
  assert_eq(observed.length(), count)
  assert_true(@strategy.captured_dag_strategy(run) is None)
  @host_driver.commit_adaptive_policy_choice(policy, None).unwrap()
  assert_true(@strategy.captured_dag_strategy(run) is Some(_))
  assert_eq(@strategy.strategy_history_count(run), 1)
  @strategy.stop_captured_dag(run)
  assert_true(@strategy.retire_captured_task_outputs(run))
  @connector.close_capability_registry(registry)
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
