///|
test "independent numeric and Local bundles use the same installed Host without backend dispatch branches" {
  for cancel in [false, true] {
    let (run, _) = captured_graph_fixture()
    let driver = @host_driver.open_dispatch_driver(run)
    let generated = dispatch_test_generated(run)
    let limits = dispatch_test_limits()
    let mut numeric_installation = None
    let mut local_installation = None
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
          @host_driver.DispatchHost[Unit, @strategy.RunIssue],
          @host_driver.PreparedTaskDispatch,
        ) -> Result[Unit, @strategy.RunIssue],
      ],
    ] = [
      {
        name: "independent-numeric",
        acquisition: None,
        fixed_compute: Some(fn(registry, registration) {
          let configured = @builtin.configure_compute_modules(
            driver,
            registry,
            1,
            _ => @strategy.RunIssue::ForeignCandidate,
            with_reference_compute=Some(
              (
                registration,
                {
                  sequences: generated,
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
                issue => issue,
                issue => issue,
              ),
            ),
          ).unwrap()
          assert_eq(@builtin.configured_compute_module_keys(configured), [
            "reference_compute",
          ]) catch {
            _ => abort("configured subset included an absent implementation")
          }
          let implementation = @builtin.configured_reference_compute_module(
            configured,
          ).unwrap()
          numeric_installation = Some(implementation)
          fn(host, task) {
            let before = @resources.ledger_usage(
              @strategy.captured_dag_ledger(run),
            )
            assert_true(
              @builtin.dispatch_local(configured, host, task)
              is Err(MissingImplementation),
            ) catch {
              _ => abort("absent implementation accepted")
            }
            assert_eq(
              @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
              before,
            ) catch {
              _ => abort("absent implementation changed ledger")
            }
            if cancel {
              // Host cancellation is an input stimulus. Concrete attempt,
              // settlement and publication are owned by the installed module.
              // Post-start cancellation order is covered by reference_execution.
              @host_driver.stop_dispatch_driver(driver)
            }
            @builtin.dispatch_reference_compute(configured, host, task).map_err(_ => {
                @strategy.RunIssue::Stopped
              },
            )
          }
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
          let estimates = @local_driver.prepare_local_estimate_module(
            implementation,
            connector_test_schedules(
              @local_driver.local_dispatch_work_slots(),
              10L,
            ),
            1000,
          ).unwrap()
          @local_driver.install_local_dispatch_estimates(
            implementation, estimates,
          ).unwrap()
          local_installation = Some(implementation)
          fn(host, task) {
            @local_driver.execute_local_dispatch(implementation, host, task).map_err(_ => {
                @strategy.RunIssue::ForeignCandidate
              },
            )
          }
        }),
      },
    ]
    let installed = @connector.install_bundles(manifest, 2, 100).unwrap()
    manifest.clear()
    let registry = @connector.installed_bundle_registry(installed)
    let entries = @connector.installed_compute_implementations(installed)
    let local_entry = Some(
      (
        local_installation.unwrap(),
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    )
    let numeric_entry = Some(
      (numeric_installation.unwrap(), issue => issue, issue => issue),
    )
    assert_true(
      @builtin.assemble_compute_contributions(
        registry,
        1,
        with_local=local_entry,
        with_reference_compute=numeric_entry,
      )
      is Err(EntryLimit),
    )
    assert_true(
      @builtin.assemble_compute_contributions(
        search_registry(),
        2,
        with_local=local_entry,
        with_reference_compute=numeric_entry,
      )
      is Err(ForeignRegistration(_)),
    )
    let contributions = @builtin.assemble_compute_contributions(
      registry,
      2,
      with_local=local_entry,
      with_reference_compute=numeric_entry,
    ).unwrap()
    let runtime = @host_driver.open_compute_host(
      driver,
      registry,
      contributions,
      limits.capacity,
      100,
      10000,
      2,
    ).unwrap()
    let host = @host_driver.compute_host_dispatch(runtime)
    @host_driver.configure_compute_host_estimates(
      runtime,
      [Some(1000), Some(1000), Some(1000)],
      { max_offers: 5, max_strategies: 4, max_work: 1000, max_revisions: 3, },
      0,
    ).unwrap()
    @host_driver.refresh_compute_host(runtime).unwrap()
    let after_selection = @resources.ledger_usage(
      @strategy.captured_dag_ledger(run),
    )
    @host_driver.refresh_compute_host(runtime).unwrap()
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
    while @host_driver.prepare_next_compute_task(runtime, ()).unwrap()
          is Some(task) {
      let implementation = @connector.capability_implementation(
        entries,
        @host_driver.prepared_task_registration(task),
      ).unwrap()
      dispatched += 1
      match implementation(host, task) {
        Ok(_) => @host_driver.refresh_compute_host(runtime).unwrap()
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
