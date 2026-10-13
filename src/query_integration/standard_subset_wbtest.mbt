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
  let (run, _) = captured_graph_fixture(numeric_dag=true)
  let installed = @conformance.configure_subset(
    run,
    dispatch_test_generated(run),
    0,
  )
  let runtime = @builtin.configured_host_runtime(installed)
  let ledger = @strategy.captured_dag_ledger(run)
  let before = @resources.ledger_usage(ledger)
  let budget = @resources.ledger_admission_limits(ledger)
  assert_eq(budget.retained_bytes, 32000000L)
  assert_eq(@host_driver.compute_host_exclusions(runtime, 100).unwrap(), [])
  assert_true(
    @host_driver.prepare_next_compute_task(runtime, ())
    is Err(Estimate(NoStrategy)),
  )
  // Independent allocation arithmetic from the installed literal limits:
  // generated_sequence_capacity: three retained node inventories and text;
  // local_import_retention_capacity: row/node views plus five byte inventories.
  // These are conservative contract allocations, not measured output or RSS.
  let generated_retention = 256L * (10000L + 10000L + 10000L) + 8L * 10000L
  let imported_retention = 64L *
    (100L + 10000L + 10000L + 100L + 10000L + 10000L) +
    8L * (10000L + 10000L + 10000L + 10000L + 10000L)
  // compute_b and compute_c are published; compute_a stays alive until compute_c
  // commits. All three allocations coexist at that completion boundary.
  let required = 3L * (generated_retention + imported_retention)
  assert_eq(required, 32198400L)
  assert_true(required > budget.retained_bytes)
  assert_eq(@strategy.strategy_report_count(run), 1)
  let assessment = @strategy.strategy_report_at(run, 0).unwrap()
  assert_eq(assessment.rejection, Some(@resources.RetentionLimit))
  assert_eq(assessment.retained_bytes, required + before.held_bytes)
  for task in [1, 2, 3] {
    assert_false(@strategy.captured_task_completed(run, task))
    assert_true(@strategy.captured_task_output(run, task, Step(1)) is None)
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.stop_captured_dag(run)
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.transferred_bytes, before.transferred_bytes)
  assert_eq(after.held_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.reserved_retention_bytes, 0L)
}
