///|
test "independent numeric and Local bundles use the same installed Host without backend dispatch branches" {
  for cancel in [false, true] {
    let (run, _) = captured_graph_fixture()
    let driver = @host_driver.open_dispatch_driver(run)
    let generated = dispatch_test_generated(run)
    let limits = dispatch_test_limits()
    let measurement : @execution.FixedInputGuardMeasureLimits = {
      max_work: 100,
      max_bytes: 100,
      max_nodes: 100,
      max_depth: 10,
    }
    let manifest : Array[
      @connector.CapabilityBundle[
        Unit,
        (
          (
            Unit,
            Int,
            @strategy.StrategyRevision,
            @connector.FixedComputeRequest,
          ) -> Result[@host_driver.DispatchWork, @strategy.RunIssue],
          (
            @host_driver.DispatchHost[Unit, @strategy.RunIssue],
            @host_driver.PreparedTaskDispatch,
          ) -> Result[Unit, @strategy.RunIssue],
          (Unit, Int, @host_driver.TaskEstimateQuantities) -> Result[
            Array[@strategy.TaskOffer],
            @strategy.RunIssue,
          ],
        ),
      ],
    ] = [
      {
        name: "independent-numeric",
        acquisition: None,
        fixed_compute: Some(fn(registry, registration) {
          let implementation = @reference_driver.prepare_numeric_dispatch_module(
            driver,
            registry,
            registration,
            generated,
            {
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
            limits.native_query.expressions,
          ).unwrap()
          (
            fn(_context, task, revision, request) {
              @reference_driver.prepare_numeric_dispatch(
                implementation, task, revision, request,
              )
            },
            fn(host, task) {
              let (attempt, execution) = @reference_driver.start_numeric_dispatch(
                implementation, host, task,
              ).unwrap()
              if cancel {
                @strategy.close_task_execution(run, execution)
                assert_true(
                  @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes >
                  0L,
                ) catch {
                  _ => abort("reservation released before settlement")
                }
                @strategy.settle_task_execution(run, execution, true).unwrap()
                Err(@strategy.RunIssue::Stopped)
              } else {
                @reference_compute.execute_numeric_attempt(attempt).unwrap()
                @strategy.settle_task_execution(run, execution, true).unwrap()
                @strategy.complete_task_execution(run, execution)
              }
            },
            fn(_context, task, _quantities) {
              @reference_driver.estimate_numeric_dispatch_offer(
                implementation,
                task,
                Some(1L),
                100,
              ).map(offer => {
                match offer {
                  Some(value) => [value]
                  None => []
                }
              })
            },
          )
        }),
      },
      {
        name: "local-implementation",
        acquisition: None,
        fixed_compute: Some(fn(registry, registration) {
          let implementation = @local_driver.prepare_local_dispatch_module(
            driver,
            registry,
            registration,
            generated,
            limits.local_execution,
            limits.guards,
            limits.candidate_work,
          ).unwrap()
          (
            fn(_context, task, revision, request) {
              @local_driver.prepare_local_dispatch(
                implementation, task, revision, request,
              ).map_err(_ => @strategy.RunIssue::ForeignCandidate)
            },
            fn(host, task) {
              @local_driver.execute_local_dispatch(implementation, host, task).map_err(_ => {
                  @strategy.RunIssue::ForeignCandidate
                },
              )
            },
            fn(_context, task, _quantities) {
              @local_driver.estimate_local_dispatch_offer(
                implementation,
                task,
                [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(10L), }],
                100,
              )
              .map(offer => [offer])
              .map_err(_ => @strategy.RunIssue::ForeignCandidate)
            },
          )
        }),
      },
    ]
    let installed = @connector.install_bundles(manifest, 2, 100).unwrap()
    manifest.clear()
    let registry = @connector.installed_bundle_registry(installed)
    let entries = @connector.installed_compute_implementations(installed)
    let contributions = @connector.project_capability_implementations(
      entries,
      entry => @host_driver.ComputeContribution::{
        prepare: entry.0,
        propose: entry.2,
      },
      2,
    ).unwrap()
    let preparations = @connector.project_capability_implementations(
      contributions,
      entry => entry.prepare,
      2,
    ).unwrap()
    let host = @host_driver.open_dispatch_host(
      driver,
      preparations,
      limits.capacity,
      100,
      10000,
    ).unwrap()
    let offer_installation = @connector.project_capability_implementations(
      contributions,
      entry => entry.propose,
      2,
    ).unwrap()
    let policy = @host_driver.open_adaptive_dispatch(
      driver,
      registry,
      offer_installation,
      [Some(1000), Some(1000), Some(1000)],
      { max_offers: 5, max_strategies: 4, max_work: 1000, max_revisions: 3, },
      0,
    ).unwrap()
    @host_driver.refresh_adaptive_dispatch(policy).unwrap()
    let after_selection = @resources.ledger_usage(
      @strategy.captured_dag_ledger(run),
    )
    @host_driver.refresh_adaptive_dispatch(policy).unwrap()
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
      after_selection,
    )
    // The same adaptive Host selects numeric A/B and Local C from pure
    // registered proposals, then refreshes only after real state progress.
    let revision = @strategy.captured_dag_strategy(run).unwrap()
    for (task, index) in [(1, 0), (2, 0), (3, 1)] {
      assert_true(
        physical_equal(
          @strategy.strategy_registration(revision, task).unwrap(),
          @connector.capability_registration_at(registry, index).unwrap(),
        ),
      )
    }
    let mut dispatched = 0
    while @host_driver.prepare_next_installed_task(host, ()).unwrap()
          is Some(task) {
      let implementation = @connector.capability_implementation(
        entries,
        @host_driver.prepared_task_registration(task),
      ).unwrap()
      dispatched += 1
      match (implementation.1)(host, task) {
        Ok(_) => @host_driver.refresh_adaptive_dispatch(policy).unwrap()
        Err(_) => {
          @host_driver.stop_dispatch_driver(driver)
          break
        }
      }
    }
    assert_eq(dispatched, if cancel { 1 } else { 3 })
    if cancel {
      assert_false(@strategy.captured_task_completed(run, 1))
      assert_false(@strategy.captured_task_completed(run, 2))
    } else {
      let output = @strategy.captured_task_output(run, 3, Step(1)).unwrap()
      assert_eq(@execution.completed_row_count(output), 1)
      assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3.0)))
      for task in [3, 2, 1] {
        @strategy.close_captured_task_output(run, task)
      }
    }
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.held_bytes, 0L)
  }
}
