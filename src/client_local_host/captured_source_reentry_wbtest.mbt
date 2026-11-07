///|
test "captured binding rechecks DAG Source port after original verifier callback" {
  let value = captured_tasks_fixture()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(value.setup),
  )
  let attempts = @resources.ledger_usage(value.ledger).attempts
  value.verify_hook.val = Some(() => {
    @strategy.close_captured_task_output(run, 0)
  })
  let available = @row_source_host.check_row_capture_compute_binding(
    value.capture,
    run,
    0,
  )
  // Closing the DAG port does not close the independently owned RowRun.
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  assert_eq(@resources.ledger_usage(value.ledger).attempts, attempts)
  assert_true(close_local_values_tasks(run, []))
  captured_tasks_close_source(value)
  assert_false(available)
}

///|
test "captured execution refuses verifier-retired DAG Source without advancing tasks" {
  let value = captured_tasks_fixture()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(value.setup),
  )
  let attempts = @resources.ledger_usage(value.ledger).attempts
  value.verify_hook.val = Some(() => {
    @strategy.close_captured_task_output(run, 0)
  })
  guard execute_captured_local_tasks_guarded(
      value.setup,
      value.capture,
      value.requirements,
      64,
      100000,
      () => true,
    )
    is Err(failure) else {
    fail("verifier-retired Source port must fence Compute")
  }
  assert_true(local_values_execution_failure_issue(failure) is Fenced)
  assert_eq(@resources.ledger_usage(value.ledger).attempts, attempts)
  assert_false(@strategy.captured_task_completed(run, 1))
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  captured_tasks_close_source(value)
}

///|
test "captured Source identity remains observable after stop without port retirement" {
  let value = captured_tasks_fixture()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(value.setup),
  )
  let source = @row_source_host.row_capture_source(value.capture).unwrap()
  value.verify_hook.val = Some(() => @strategy.stop_captured_dag(run))
  assert_true(@strategy.captured_task_source_matches(run, 0, source))
  assert_true(
    @row_source_host.check_row_capture_compute_binding(value.capture, run, 0),
  )
  assert_true(@strategy.next_captured_task(run) is None)
  assert_eq(@resources.ledger_usage(value.ledger).attempts, 1)
  assert_true(close_local_values_tasks(run, []))
  captured_tasks_close_source(value)
}
