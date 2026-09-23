///|
test "Compute-only bundle executes a shared captured DAG through common Host dispatch" {
  let (run, _) = captured_graph_fixture()
  let generated = dispatch_test_generated(run)
  let limits = dispatch_test_limits()
  let manifest : Array[
    @connector.CapabilityBundle[
      Unit,
      (Unit, Int, @strategy.StrategyRevision, @connector.FixedComputeRequest) -> Result[
        @connector.SynchronousCompute,
        @local_connector.LocalModuleIssue,
      ],
      Unit,
    ],
  ] = [
    {
      name: "installed-compute",
      acquisition: None,
      fixed_compute: Some(fn(registry, registration) {
        let implementation = @local_connector.prepare_local_compute_module(
          registry,
          registration,
          generated,
          limits.local_execution,
          limits.guards,
          limits.candidate_work,
          generated.length(),
        ).unwrap()
        fn(_context, task, _revision, request) {
          @local_connector.prepare_local_module_compute(
            implementation,
            task - 1,
            request,
            None,
          )
        }
      }),
      effect: None,
    },
  ]
  let installed = @connector.install_bundles(manifest, 1, 100).unwrap()
  manifest.clear()
  let registry = @connector.installed_bundle_registry(installed)
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let implementations = @connector.installed_compute_implementations(installed)
  @strategy.configure_strategy_search(run, {
    max_offers: 3,
    max_strategies: 1,
    max_work: 1000,
    max_revisions: 1,
  }).unwrap()
  let offers = [1, 2, 3].map(task => {
    @strategy.prepare_task_offer(
      run,
      task,
      registration,
      1,
      [{ work_slots: [0], milliseconds: Some(1L), }],
      {
        transfer_bytes: 0L,
        retained_bytes: 8000000L,
        execution_bytes: 64000000L,
      },
      100,
    ).unwrap()
  })
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None) is Ok(Selected(_)),
  )
  let revision = @strategy.captured_dag_strategy(run).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  for task in [1, 2, 3] {
    let (ticket, compute) = @host_driver.prepare_installed_dispatch(
      driver,
      implementations,
      (),
      task,
      revision,
      limits.capacity,
      100,
      10000,
    ).unwrap()
    @host_driver.consume_dispatch_ticket(driver, ticket).unwrap()
    @strategy.execute_captured_synchronous_task(run, task, compute).unwrap()
  }
  assert_eq(
    @execution.completed_row_count(
      @strategy.captured_task_output(run, 3, Step(1)).unwrap(),
    ),
    1,
  )
}
