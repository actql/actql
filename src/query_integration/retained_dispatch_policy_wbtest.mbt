///|
test "resident offer retains independent file work without charging file bytes as DB copies" {
  for file_ms in [Some(7L), None] {
    let (run, _) = captured_graph_fixture()
    let registry = search_registry()
    let registration = @connector.capability_registration_at(registry, 1).unwrap()
    let profile = portfolio_profile(
      run,
      @connector.prepare_resource_binding(registry, registration).unwrap(),
      0L,
      0L,
      0L,
    )
    let lines : Array[@cost.SerialEstimateLine] = [
      { work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(19L), },
    ]
    let offers = Array::makei(3, index => {
      @duckdb_driver.estimate_duckdb_task_offer(
        run,
        index + 1,
        registration,
        lines,
        { transfer_bytes: 100L, retained_bytes: 100L, execution_bytes: 2000L, },
        1000,
        resident=profile,
        resident_copy_bytes=300L,
        retained_output=(1000L, file_ms),
      ).unwrap()
    })
    assert_eq(lines.length(), 1)
    for invalid in [(0L, Some(1L)), (1L, Some(-1L)), (2147483648L, None)] {
      assert_true(
        @duckdb_driver.estimate_duckdb_task_offer(
          run,
          1,
          registration,
          lines,
          {
            transfer_bytes: 100L,
            retained_bytes: 100L,
            execution_bytes: 2000L,
          },
          1000,
          resident=profile,
          resident_copy_bytes=300L,
          retained_output=invalid,
        )
        is Err(InvalidCapacity),
      )
    }
    @strategy.configure_strategy_search(run, {
      max_offers: 3,
      max_strategies: 1,
      max_work: 10000,
      max_revisions: 1,
    }).unwrap()
    // Each independent file exceeds the DB's entire 1000-byte copy capacity.
    // Selection is nevertheless valid because only the 100-byte copies live
    // inside that environment, while the independent holdings remain charged.
    assert_true(
      @strategy.revise_strategy(run, offers, registry, Some([0])).unwrap()
      is Selected(_),
    )
    assert_eq(
      @strategy.strategy_task_envelope(run, 1).unwrap().retained_bytes,
      1100L,
    )
    let assessment = @strategy.strategy_assessment(
      @strategy.captured_dag_strategy(run).unwrap(),
    )
    if file_ms is Some(_) {
      assert_true(assessment.duration is Complete(78L))
    } else {
      assert_true(assessment.duration is Unknown)
    }
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
      0,
    )
  }
}

///|
test "retained output policy contributes file work and capacity before selection" {
  for file_ms in [Some(7L), None] {
    let (run, _) = captured_graph_fixture()
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
    assert_true(
      @duckdb_driver.configure_duckdb_retained_output(installed, 0L, file_ms)
      is Err(InvalidConfiguration),
    )
    @duckdb_driver.configure_duckdb_retained_output(installed, 50L, file_ms).unwrap()
    assert_true(
      @duckdb_driver.configure_duckdb_retained_output(installed, 51L, file_ms)
      is Err(InvalidConfiguration),
    )
    assert_eq(
      @duckdb_driver.duckdb_dispatch_rejection(installed, 1, resident=true),
      None,
    )
    let policy = @duckdb_driver.prepare_duckdb_estimate_module(
      installed,
      connector_test_schedules(@duckdb_driver.duckdb_dispatch_work_slots(), 19L),
      Array::make(3, @strategy.PhysicalEnvelope::{
        transfer_bytes: 100L,
        retained_bytes: 100L,
        execution_bytes: 2000L,
      }),
      1000,
    ).unwrap()
    @duckdb_driver.install_duckdb_dispatch_estimates(installed, policy).unwrap()
    let offers = Array::makei(3, index => {
      @duckdb_driver.estimate_duckdb_installed_offers(installed, index + 1, {
        rows: None,
        wire_bytes: None,
        pairs: None,
      }).unwrap()[0]
    })
    @strategy.configure_strategy_search(run, {
      max_offers: 3,
      max_strategies: 1,
      max_work: 10000,
      max_revisions: 1,
    }).unwrap()
    @strategy.revise_strategy(run, offers, registry, Some([0])).unwrap()
    |> ignore
    let assessment = @strategy.strategy_assessment(
      @strategy.captured_dag_strategy(run).unwrap(),
    )
    if file_ms is Some(_) {
      assert_true(assessment.duration is Complete(78L))
    } else {
      assert_true(assessment.duration is Unknown)
    }
    assert_eq(
      @strategy.strategy_task_envelope(run, 1).unwrap().retained_bytes,
      150L,
    )
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
      0,
    )
    let entries = @connector.install_capability_implementations(
      registry,
      [
        (
          registration,
          fn(_ : Unit, task, revision, request) {
            @duckdb_driver.prepare_duckdb_dispatch(
              installed, task, revision, request,
            )
          },
        ),
      ],
      1,
    ).unwrap()
    let host = @host_driver.open_dispatch_host(
      driver,
      entries,
      duckdb_dispatch_module_limits().capacity,
      100,
      10000,
    ).unwrap()
    let task = @host_driver.prepare_next_installed_task(host, ())
      .unwrap()
      .unwrap()
    let setup = @duckdb_driver.take_duckdb_dispatch(installed, host, task).unwrap()
    assert_eq(
      @duckdb_driver.configured_strategy_output_file_bytes(setup),
      Some(50L),
    )
    for actual in [0L, 49L, 51L] {
      assert_true(
        @duckdb_driver.start_configured_strategy_compute_host(
          setup,
          _ => false,
          100L,
          2000L,
          retained_storage=(actual, () => true),
        )
        is Err(Physical(InvalidCharge)),
      )
    }
    assert_true(
      @duckdb_driver.start_configured_strategy_compute_host(
        setup,
        _ => false,
        100L,
        2000L,
      )
      is Err(Physical(InvalidCharge)),
    )
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
      0,
    )
  }
}

///|
test "resident copy minimum does not inflate the fresh retained offer" {
  for alternative in [0, 1] {
    let (run, _) = captured_graph_fixture()
    let registry = search_registry()
    let registration = @connector.capability_registration_at(registry, 1).unwrap()
    let installed = @duckdb_driver.prepare_duckdb_dispatch_module(
      @host_driver.open_dispatch_driver(run),
      registry,
      registration,
      dispatch_test_generated(run).map(
        @execution.generated_completion_preparation,
      ),
      duckdb_dispatch_module_limits(),
    ).unwrap()
    @duckdb_driver.configure_duckdb_retained_output(installed, 50L, Some(0L)).unwrap()
    @duckdb_driver.install_duckdb_resident_estimates(
      installed,
      portfolio_profile(
        run,
        @connector.prepare_resource_binding(registry, registration).unwrap(),
        0L,
        0L,
        0L,
      ),
      connector_test_schedules(@duckdb_driver.duckdb_dispatch_work_slots(), 19L),
    ).unwrap()
    let policy = @duckdb_driver.prepare_duckdb_estimate_module(
      installed,
      connector_test_schedules(@duckdb_driver.duckdb_dispatch_work_slots(), 19L),
      Array::make(3, @strategy.PhysicalEnvelope::{
        transfer_bytes: 100L,
        retained_bytes: 100L,
        execution_bytes: 2000L,
      }),
      1000,
    ).unwrap()
    let offers = Array::makei(3, index => {
      let candidates = @duckdb_driver.estimate_duckdb_module_offers(
        policy,
        index + 1,
        { rows: None, wire_bytes: None, pairs: None, },
      ).unwrap()
      assert_eq(candidates.length(), 2)
      candidates[alternative]
    })
    @strategy.configure_strategy_search(run, {
      max_offers: 3,
      max_strategies: 1,
      max_work: 10000,
      max_revisions: 1,
    }).unwrap()
    let result = @strategy.revise_strategy(run, offers, registry, Some([0])).unwrap()
    if alternative == 0 {
      assert_true(result is Selected(_))
      assert_eq(
        @strategy.strategy_task_envelope(run, 1).unwrap().retained_bytes,
        150L,
      )
    } else {
      // This fixture's 1000-byte DB cannot hold the real copy allowance.
      // Metadata alone must not authorize resident execution.
      assert_true(result is NoFeasible)
    }
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
      0,
    )
  }
}
