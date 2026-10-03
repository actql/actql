///|
test "managed finished imports release owned roots while operation handles survive" {
  for phase in 0..<3 {
    let (run, issuer) = captured_graph_fixture(
      local_values_two_consumer_chain=true,
      local_values_two_consumer_relation_variant="select",
    )
    let registry = search_registry()
    let limits = dispatch_test_limits()
    let installed = @local_driver.prepare_local_dispatch_module(
      @host_driver.open_dispatch_driver(run),
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      dispatch_test_generated(run),
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
    ).unwrap()
    @local_driver.configure_local_retained_inputs(
      installed,
      {
        max_rows: 100,
        values: limits.local_execution.rows.input_values,
        wire: retained_attempt_wire_limits(),
        row: {
          max_bytes: 100,
          max_nodes: 20,
          max_depth: 4,
          max_text_bytes: 100,
        },
        max_batch_bytes: 64,
      },
      None,
    ).unwrap()
    let producer_live = Ref(true)
    let (producer_operations, producer) = run_local_managed_test_task(
      installed,
      run,
      1,
      [],
      [],
      1,
      producer_live,
    )
    let rows = local_managed_test_rows(producer_operations)
    assert_eq(rows.length(), 2)
    let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    let operations = start_local_managed_test_task_operations(
      installed,
      run,
      2,
      [producer],
      [rows],
      require_provider=true,
    )
    // Keep both the operation record and one returned transfer across release.
    // Finishing has populated the bridge and the driver's checked read array.
    let transfer = operations.inputs[0]
    assert_eq(operations.inputs.length(), 1)
    if phase == 1 {
      assert_false((operations.advance)(1).unwrap().complete)
    } else if phase == 2 {
      (operations.execute)().unwrap()
      assert_eq((operations.output_rows)(), 2)
    }
    let work = (operations.cumulative_provider_work)().unwrap()
    let admitted = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_true(
      admitted.reserved_execution_bytes > before.reserved_execution_bytes,
    )
    assert_true((operations.request_cancel)())
    if phase == 1 {
      assert_true((operations.advance)(1) is Err(_))
    }
    assert_true((operations.execution_stopped)())
    let stopped_work = (operations.cumulative_provider_work)().unwrap()
    assert_true(stopped_work >= work)
    // Closing a scope alone cannot refund an unsettled execution.
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
      admitted.reserved_execution_bytes,
    )
    (operations.settle)().unwrap()
    if phase != 0 {
      // The provider still owns scratch until the explicit cleanup call.
      assert_eq(
        @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
        admitted.reserved_execution_bytes,
      )
    }
    guard (operations.cleanup_refresh)() else {
      fail("Managed import scratch remained after cleanup")
    }
    let released = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(
      released.reserved_execution_bytes,
      before.reserved_execution_bytes,
    )
    assert_eq((operations.cumulative_provider_work)().unwrap(), stopped_work)
    assert_eq((operations.output_rows)(), 0)
    assert_true((operations.output_row)(0) is Err(_))
    assert_true((transfer.append)(rows[0]) is Err(_))
    assert_true((transfer.finish)() is Err(_))
    assert_true((operations.cleanup_refresh)())
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
      released.reserved_execution_bytes,
    )
    // Cleanup must not clear another owner's successfully published storage.
    assert_true(@execution.managed_completed_output_available(producer))
    assert_eq(local_managed_test_rows(producer_operations), rows)
    producer_live.val = false
    @strategy.close_captured_task_output(run, 1)
    (producer_operations.close)()
    assert_true((producer_operations.cleanup_refresh)())
    @strategy.stop_captured_dag(run)
    for task in [0, 2, 3, 4] {
      @strategy.close_captured_task_output(run, task)
    }
    @strategy.refresh_captured_retention(run)
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
      0L,
    )
    @mock.close_mock_query_issuer(issuer)
  }
}

///|
test "managed success releases import and admission scratch while retained output remains readable" {
  let (run, issuer) = captured_graph_fixture(
    local_values_two_consumer_chain=true,
    local_values_two_consumer_relation_variant="select",
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  let producer_live = Ref(true)
  let (producer_operations, producer) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    producer_live,
  )
  let rows = local_managed_test_rows(producer_operations)
  assert_eq(rows.length(), 2)
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  let operations = start_local_managed_test_task_operations(
    installed,
    run,
    2,
    [producer],
    [rows],
    require_provider=true,
  )
  let transfer = operations.inputs[0]
  let output_live = Ref(true)
  (operations.execute)().unwrap()
  let work = (operations.cumulative_provider_work)().unwrap()
  (operations.prepare_finalization)(2, operations.storage_bytes, fn() {
    output_live.val
  }).unwrap()
  while !(operations.advance_finalization)(16).unwrap().complete {
    ()
  }
  (operations.settle)().unwrap()
  let completed = (operations.complete)(2, operations.storage_bytes, fn() {
    output_live.val
  }).unwrap()
  let published = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(published.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq((operations.cumulative_provider_work)().unwrap(), work)
  assert_true(@execution.managed_completed_output_available(completed))
  assert_eq(local_managed_test_rows(operations), rows)
  assert_true((transfer.append)(rows[0]) is Err(_))
  assert_true((transfer.finish)() is Err(_))
  // Disposing the execution cannot discard a still-published output generation.
  // Its existing owner must keep the readable backing until the output closes.
  (operations.close)()
  assert_false((operations.cleanup_refresh)())
  assert_true(@execution.managed_completed_output_available(completed))
  assert_eq(local_managed_test_rows(operations), rows)
  output_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (operations.close)()
  assert_true((operations.cleanup_refresh)())
  let released = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(
    released.reserved_execution_bytes,
    published.reserved_execution_bytes,
  )
  assert_eq(released.transferred_bytes, published.transferred_bytes)
  assert_true((operations.cleanup_refresh)())
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
    released,
  )
  assert_true(@execution.managed_completed_output_available(producer))
  assert_eq(local_managed_test_rows(producer_operations), rows)
  producer_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (producer_operations.close)()
  assert_true((producer_operations.cleanup_refresh)())
  @strategy.stop_captured_dag(run)
  for task in [0, 3, 4] {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
    0L,
  )
  @mock.close_mock_query_issuer(issuer)
}
