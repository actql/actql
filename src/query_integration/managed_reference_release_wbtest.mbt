///|
test "reference managed finished import releases through common cleanup with transfer handles retained" {
  for phase in 0..<2 {
    let (run, issuer) = captured_graph_fixture(
      dag_two_consumers_of_compute_a=true,
    )
    // Install the two concrete modules without configuring Host estimate search;
    // this test explicitly selects each managed dispatch through its own module.
    let registry = search_registry()
    let driver = @host_driver.open_dispatch_driver(run)
    let sequences = dispatch_test_generated(run)
    let limits = dispatch_test_limits()
    let local_module = @local_driver.prepare_local_dispatch_module(
      driver,
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      sequences,
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
    ).unwrap()
    @local_driver.configure_local_retained_inputs(
      local_module,
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
    let numeric_module = @reference_driver.prepare_numeric_dispatch_module(
      driver,
      registry,
      @connector.capability_registration_at(registry, 1).unwrap(),
      sequences.map(@execution.generated_completion_preparation),
      {
        max_work: 100,
        max_entries: 100,
        max_name_bytes: 10000,
        values: limits.local_execution.rows.input_values,
        physical: limits.guards,
        roots: limits.guards,
      },
      native_compile_limits().expressions,
    ).unwrap()
    let numeric = @reference_driver.prepare_numeric_contribution(
      numeric_module,
      Some(1L),
      100,
    ).unwrap()
    let producer_live = Ref(true)
    let (producer_operations, producer) = run_local_managed_test_task(
      local_module,
      run,
      1,
      [],
      [],
      1,
      producer_live,
      ordered_outputs=Some([
        @local_driver.local_managed_captured_relation_input(),
      ]),
    )
    let rows = local_managed_test_rows(producer_operations)
    assert_eq(rows, ["{\"id\":3}"])
    assert_eq(@strategy.next_captured_task(run), Some(2))
    assert_eq(
      @strategy.graph_task_selected_step(@strategy.captured_dag_graph(run), 2),
      None,
    )
    let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 2).unwrap()
    @reference_compute.prepare_numeric_plan(
      owner,
      100,
      10000,
      native_compile_limits().expressions,
    ).unwrap()
    |> ignore
    // This cancellation-only task requests the reference implementation's
    // supported no-identity profile, not process-managed deferred CID custody.
    let obligations = @execution.prepare_managed_obligations(
      owner,
      [],
      @execution.ManagedUse,
      @execution.MaterialBinding,
      0,
    ).unwrap()
    let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    let prepared = @reference_driver.prepare_numeric_managed_dispatch(
        numeric,
        [producer],
        obligations,
        0L,
      )
      .unwrap()
      .unwrap()
    let operations = @reference_driver.start_numeric_managed_dispatch_node(
      prepared,
    ).unwrap()
    assert_eq(operations.inputs.length(), 1)
    // Retain the actual returned operation/transfer closures through cleanup.
    // Finish leaves a nonempty admitted bridge and checked read owned by this
    // numeric invocation, independently of the still-published Local producer.
    let transfer = operations.inputs[0]
    for row in rows {
      (transfer.append)(row).unwrap()
    }
    (transfer.finish)().unwrap()
    if phase == 1 {
      (operations.execute)().unwrap()
      assert_eq((operations.output_rows)(), 1)
    }
    let admitted = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_true(
      admitted.reserved_execution_bytes > before.reserved_execution_bytes,
    )
    assert_true(admitted.transferred_bytes > before.transferred_bytes)
    assert_false(@strategy.captured_task_completed(run, 2))
    (operations.close)()
    assert_false((operations.cleanup_refresh)())
    let pending = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(
      pending.reserved_execution_bytes,
      admitted.reserved_execution_bytes,
    )
    assert_eq(pending.transferred_bytes, admitted.transferred_bytes)
    assert_true((operations.execute)() is Err(_))
    (operations.settle)().unwrap()
    guard (operations.cleanup_refresh)() else {
      fail("Reference import scratch remained after cleanup")
    }
    let released = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(
      released.reserved_execution_bytes,
      before.reserved_execution_bytes,
    )
    assert_eq(released.transferred_bytes, admitted.transferred_bytes)
    assert_eq((operations.output_rows)(), 0)
    assert_true((operations.output_row)(0) is Err(_))
    assert_true((transfer.append)(rows[0]) is Err(_))
    assert_true((transfer.finish)() is Err(_))
    assert_true((operations.cleanup_refresh)())
    (operations.close)()
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
      released.reserved_execution_bytes,
    )
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).transferred_bytes,
      admitted.transferred_bytes,
    )
    assert_false(@strategy.captured_task_completed(run, 2))
    assert_true(@execution.managed_completed_output_available(producer))
    assert_eq(local_managed_test_rows(producer_operations), rows)
    producer_live.val = false
    @strategy.close_captured_task_output(run, 1)
    (producer_operations.close)()
    assert_true((producer_operations.cleanup_refresh)())
    @strategy.stop_captured_dag(run)
    for task in [0, 2, 3] {
      @strategy.close_captured_task_output(run, task)
    }
    @strategy.refresh_captured_retention(run)
    let final_usage = @resources.ledger_usage(
      @strategy.captured_dag_ledger(run),
    )
    assert_eq(final_usage.reserved_execution_bytes, 0L)
    assert_eq(final_usage.reserved_retention_bytes, 0L)
    assert_eq(final_usage.held_bytes, 0L)
    @mock.close_mock_query_issuer(issuer)
  }
}
