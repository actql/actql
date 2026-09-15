///|
test "standard configured Host runs Local alone reference alone and both without concrete task orchestration" {
  for mode in [0, 1, 2] {
    for cancel in [false, true] {
      let (run, _) = captured_graph_fixture(numeric_dag=true)
      let installed = @conformance.configure_subset(
        run,
        dispatch_test_generated(run),
        mode,
      )
      let runtime = @builtin.configured_host_runtime(installed)
      let first = @host_driver.prepare_next_compute_task(runtime, ())
        .unwrap()
        .unwrap()
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
