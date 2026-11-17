///|
test "captured Query consumers retire before their same original Row Source close" {
  let value = captured_tasks_fixture()
  let dag = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(value.setup),
  )
  assert_eq(
    @strategy.graph_captured_prefix(@strategy.captured_dag_graph(dag)),
    1,
  )
  @row_source_host.retain_row_capture_task(value.capture, dag, 0).unwrap()
  let before = @resources.ledger_usage(value.ledger)
  assert_true(before.held_bytes > 0L)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  assert_true(@strategy.retire_captured_task_consumers(dag))
  // The original physical owner has not closed. Its retained allocation is
  // unchanged and the complete Run still reports pending retirement.
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, before.held_bytes)
  assert_true(@strategy.captured_task_retirement_pending(dag))
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  @row_source_host.close_accounted_row_run(value.source).unwrap()
  @strategy.refresh_captured_retention(dag)
  assert_false(@strategy.captured_task_retirement_pending(dag))
  @resources.settle_capacity(value.controls_ledger, value.controls).unwrap()
  let after = @resources.ledger_usage(value.ledger)
  assert_eq(after.held_bytes, 0L)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.live_reservations, 0)
}
