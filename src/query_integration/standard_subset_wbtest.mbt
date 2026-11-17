///|
test "standard configured Host runs reference alone and both without concrete task orchestration" {
  for mode in [1, 2] {
    for cancel in [false, true] {
      let (run, _) = captured_graph_fixture(numeric_dag=true)
      let installed = @conformance.configure_subset(
        run,
        dispatch_test_generated(run),
        mode,
      )
      let runtime = @builtin.configured_host_runtime(installed)
      let first = match @host_driver.prepare_next_compute_task(runtime, ()) {
        Ok(Some(task)) => task
        Ok(None) => fail("no initial compute task")
        Err(Estimate(Implementation(Implementation(issue)))) => raise issue
        Err(Estimate(Implementation(Compute(_)))) =>
          fail("Estimate(Implementation(Compute))")
        Err(Estimate(Implementation(ForeignCandidate))) =>
          fail("Estimate(Implementation(ForeignCandidate))")
        Err(Dispatch(Implementation(Implementation(issue)))) => raise issue
        Err(Estimate(NoStrategy)) => fail("Estimate(NoStrategy)")
        Err(Dispatch(NoStrategy)) => fail("Dispatch(NoStrategy)")
        Err(_) => fail("another Host preparation refusal")
      }
      if cancel {
        @host_driver.stop_dispatch_driver(
          @builtin.configured_host_driver(installed),
        )
        assert_true(
          @builtin.execute_configured_in_process(installed, first) is Err(_),
        )
        assert_false(@strategy.captured_task_completed(run, 1))
      } else {
        @builtin.execute_configured_in_process(installed, first).unwrap()
        while @host_driver.prepare_next_compute_task(runtime, ()).unwrap()
              is Some(task) {
          @builtin.execute_configured_in_process(installed, task).unwrap()
        }
        let output = @strategy.captured_task_output(run, 3, Step(1)).unwrap()
        assert_eq(@execution.completed_row_count(output), 1)
        assert_true(
          @execution.completed_cell(output, 0, 0) is Some(Number(3.0)),
        )
      }
      for task in [3, 2, 1] {
        @strategy.close_captured_task_output(run, task)
      }
      let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
      assert_eq(usage.held_bytes, 0L)
      assert_eq(usage.reserved_execution_bytes, 0L)
      assert_eq(usage.reserved_retention_bytes, 0L)
    }
  }
}

///|
test "standard Local-only subset refuses its three-task retention peak before dispatch" {
  let (run, issuer) = captured_graph_fixture(numeric_dag=true)
  let installed = @conformance.configure_subset(
    run,
    dispatch_test_generated(run),
    0,
  )
  let runtime = @builtin.configured_host_runtime(installed)
  let ledger = @strategy.captured_dag_ledger(run)
  let budget = @resources.ledger_admission_limits(ledger)
  assert_eq(budget.retained_bytes, 32000000L)
  assert_eq(@host_driver.compute_host_exclusions(runtime, 100).unwrap(), [])
  let initial = @resources.ledger_usage(ledger)
  // Select the real installed constructors without preparing a dispatch.
  // Before-commit growth can change their startup inventory; the original
  // generic parser/import ceilings are not a permanent admission threshold.
  @host_driver.refresh_compute_host(runtime).unwrap()
  let selected = @strategy.captured_dag_strategy(run).unwrap()
  let assessed = @strategy.strategy_assessment(selected)
  assert_eq(assessed.rejection, None)
  let required = assessed.retained_bytes
  assert_true(required > 0L)
  let quoted = @resources.ledger_usage(ledger)
  assert_eq(quoted.attempts, initial.attempts)
  assert_eq(quoted.transferred_bytes, initial.transferred_bytes)
  assert_eq(quoted.held_bytes, initial.held_bytes)
  assert_eq(quoted.reserved_retention_bytes, initial.reserved_retention_bytes)
  let available = budget.retained_bytes -
    quoted.held_bytes -
    quoted.reserved_retention_bytes
  assert_true(required <= available)
  // Genuine capacity on this same Ledger leaves exactly one byte less than
  // the selected three-task peak, without changing any admission limit.
  let pressure = @resources.reserve_capacity(
    ledger,
    available - required + 1L,
    0L,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_eq(
    budget.retained_bytes - before.held_bytes - before.reserved_retention_bytes,
    required - 1L,
  )
  assert_true(
    @host_driver.prepare_next_compute_task(runtime, ())
    is Err(Estimate(NoStrategy)),
  )
  let reports = @strategy.strategy_report_count(run)
  assert_true(reports > 0)
  let assessment = @strategy.strategy_report_at(run, reports - 1).unwrap()
  assert_eq(assessment.rejection, Some(@resources.RetentionLimit))
  assert_eq(assessment.retained_bytes, required)
  for task in [1, 2, 3] {
    assert_false(@strategy.captured_task_completed(run, task))
    assert_true(@strategy.captured_task_output(run, task, Step(1)) is None)
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.stop_captured_dag(run)
  let refused = @resources.ledger_usage(ledger)
  assert_eq(refused.attempts, before.attempts)
  assert_eq(refused.transferred_bytes, before.transferred_bytes)
  assert_eq(refused.reserved_retention_bytes, before.reserved_retention_bytes)
  @resources.settle_capacity(ledger, pressure).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.transferred_bytes, before.transferred_bytes)
  assert_eq(after.held_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.reserved_retention_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
  // A refusal stops that Host. A fresh original graph recovers under the
  // same unchanged 32MB policy and must produce the actual complete Result.
  let (run, issuer) = captured_graph_fixture(numeric_dag=true)
  let installed = @conformance.configure_subset(
    run,
    dispatch_test_generated(run),
    0,
  )
  let runtime = @builtin.configured_host_runtime(installed)
  while @host_driver.prepare_next_compute_task(runtime, ()).unwrap()
        is Some(task) {
    @builtin.execute_configured_in_process(installed, task).unwrap()
  }
  let output = @strategy.captured_task_output(run, 3, Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3.0)))
  for task in [3, 2, 1] {
    @strategy.close_captured_task_output(run, task)
  }
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
}
