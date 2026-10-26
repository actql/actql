///|
test "Local finalization cancellation retains capacity through admission retirement" {
  check_local_admission_retirement(false)
}

///|
test "Local cancellation during partial receipt keeps completion unpublished" {
  check_local_admission_retirement(true)
}

///|
fn check_local_admission_retirement(partial_receipt : Bool) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    checked_program=Some(managed_import_reclamation_program()),
    preparation_work=10000,
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
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 10000,
        max_nodes: 10000,
      },
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  let operations = start_local_managed_test_task_operations(
    installed,
    run,
    1,
    [],
    [],
    require_provider=true,
  )
  (operations.execute)().unwrap()
  assert_eq((operations.output_rows)(), 100)
  (operations.prepare_finalization)(1, operations.storage_bytes, fn() { true }).unwrap()
  // Build a real admission buffer through the selected finalization path, but
  // cancel before adopting or publishing its receipt.
  let mut polls = 0
  while true {
    let poll = (operations.advance_finalization)(1).unwrap()
    polls += 1
    assert_true(polls < 10000)
    assert_true(poll.work > 0L && poll.work <= 1L)
    if partial_receipt && poll.progress == 108L {
      // All 100 rows were admitted, then eight receipt-copy entries advanced.
      // The shared cursor has not issued a receipt or adopted retained output.
      assert_false(poll.complete)
      assert_true((operations.material)() is None)
      break
    }
    if poll.complete {
      assert_false(partial_receipt)
      break
    }
  }
  let ledger = @strategy.captured_dag_ledger(run)
  let reserved = @resources.ledger_usage(ledger).reserved_execution_bytes
  assert_true(reserved > 0L)
  let work = (operations.cumulative_provider_work)().unwrap()
  assert_true((operations.request_cancel)())
  assert_true((operations.execution_stopped)())
  (operations.settle)().unwrap()
  if partial_receipt {
    // The unfinished copy still owns its admission buffer and reservation.
    assert_false((operations.cleanup_refresh)())
    assert_eq(
      @resources.ledger_usage(ledger).reserved_execution_bytes,
      reserved,
    )
  } else {
    // Ready means admission retirement completed, not receipt publication.
    // Cancellation can now reclaim scratch without an invented pending phase.
    assert_true((operations.cleanup_refresh)())
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
  assert_false(@strategy.captured_task_completed(run, 1))
  assert_true(
    (operations.complete)(1, operations.storage_bytes, fn() { true }) is Err(_),
  )
  let mut reclaimed = false
  for _ in 0..<10 {
    if (operations.cleanup_refresh)() {
      reclaimed = true
      break
    }
  }
  assert_true(reclaimed)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq((operations.cumulative_provider_work)().unwrap(), work)
  assert_true((operations.cleanup_refresh)())
  assert_false(@strategy.captured_task_completed(run, 1))
  @strategy.stop_captured_dag(run)
  for task in 0..<@strategy.graph_task_count(@strategy.captured_dag_graph(run)) {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
