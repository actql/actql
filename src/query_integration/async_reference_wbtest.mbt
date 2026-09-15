///|
test "asynchronous reference completion requires settlement and cancellation retains reservation" {
  for cancel in [false, true] {
    let (run, _) = captured_graph_fixture(numeric_dag=true)
    let installed = @conformance.configure_subset(
      run,
      dispatch_test_generated(run),
      1,
    )
    let runtime = @builtin.configured_host_runtime(installed)
    let task = @host_driver.prepare_next_compute_task(runtime, ())
      .unwrap()
      .unwrap()
    let work = @reference_driver.begin_numeric_contribution(
      @builtin.configured_reference_compute_module(
        @builtin.configured_host_modules(installed),
      ).unwrap(),
      @host_driver.compute_host_dispatch(runtime),
      task,
    ).unwrap()
    let ledger = @strategy.captured_dag_ledger(run)
    let reserved = @resources.ledger_usage(ledger)
    assert_true(reserved.reserved_execution_bytes > 0L)
    assert_true(reserved.reserved_retention_bytes > 0L)
    assert_false(@strategy.captured_task_completed(run, 1))
    if cancel {
      @reference_driver.close_async_numeric(work)
      let pending = @resources.ledger_usage(ledger)
      assert_eq(
        pending.reserved_execution_bytes,
        reserved.reserved_execution_bytes,
      )
      assert_eq(
        pending.reserved_retention_bytes,
        reserved.reserved_retention_bytes,
      )
      assert_true(@reference_driver.execute_async_numeric(work) is Err(_))
      @reference_driver.settle_async_numeric(work).unwrap()
      assert_true(@reference_driver.complete_async_numeric(work) is Err(_))
      assert_false(@strategy.captured_task_completed(run, 1))
    } else {
      @reference_driver.execute_async_numeric(work).unwrap()
      assert_false(@strategy.captured_task_completed(run, 1))
      @reference_driver.settle_async_numeric(work).unwrap()
      @reference_driver.complete_async_numeric(work).unwrap()
      assert_true(@strategy.captured_task_completed(run, 1))
      let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
      assert_eq(@execution.completed_row_count(output), 1)
      assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3.0)))
      @strategy.close_captured_task_output(run, 1)
    }
    let final_usage = @resources.ledger_usage(ledger)
    assert_eq(final_usage.held_bytes, 0L)
    assert_eq(final_usage.reserved_execution_bytes, 0L)
    assert_eq(final_usage.reserved_retention_bytes, 0L)
  }
}
