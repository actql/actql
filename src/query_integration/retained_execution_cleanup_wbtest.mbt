///|
test "task retention waits for physical cleanup independently of native stop and disposal" {
  // Successful output, failed finish, and close-before-stop have different
  // holding states. None may turn a cancellation into file cleanup evidence.
  for mode in [0, 1, 2, 3] {
    let (run, _) = captured_graph_fixture()
    let (foreign, _) = captured_graph_fixture()
    let ledger = @strategy.captured_dag_ledger(run)
    let storage_released = Ref(false)
    let transport : FixedComputeTestTransport = { settled: None, }
    let attempt = captured_graph_duckdb_try_start(
      run,
      1,
      transport,
      retained_storage=(100L, fn() { storage_released.val }),
    ).unwrap()
    let execution = @duckdb_driver.captured_duckdb_execution(attempt)
    let reserved = @resources.ledger_usage(ledger).reserved_retention_bytes
    assert_true(reserved > 100L)
    @strategy.charge_task_execution_transfer(run, execution, 7L).unwrap()
    assert_true(
      @strategy.refresh_task_execution_cleanup(run, execution)
      is Err(InvalidCharge),
    )
    if mode == 0 || mode == 1 {
      if mode == 0 {
        let compute = @duckdb_driver.captured_duckdb_attempt(attempt)
        assert_true(
          @duckdb_compute.begin_duckdb_compute_result(compute, [
            ("id", @duckdb.Float64),
          ])
          is Err(InvalidState),
        )
        let held = receive_retained_attempt(compute, Ref(true))
        @duckdb_compute.stage_retained_duckdb_compute_material(
          compute,
          @execution.retained_output_material(held),
        ).unwrap()
        transport.settled = Some(
          @duckdb_driver.captured_duckdb_attempt(attempt),
        )
      }
      @strategy.settle_task_execution(run, execution, true).unwrap()
      let completed = @duckdb_driver.complete_captured_duckdb_task(run, attempt)
      if mode == 0 {
        assert_true(completed is Ok(_))
        assert_true(@strategy.captured_task_output(run, 1, Step(1)) is Some(_))
      } else {
        assert_true(completed is Err(_))
      }
      // The completed file is exactly [{"id":3}] (10 UTF-8 bytes),
      // rather than the reserved 100-byte ceiling. Missing material must not
      // create a holding at all, and retains the full reservation instead.
      assert_eq(
        @resources.ledger_usage(ledger).held_bytes,
        if mode == 0 {
          reserved - 100L + 10L
        } else {
          0L
        },
      )
    }
    if mode == 3 {
      // Storage confirmation can arrive first. It must not settle native work.
      storage_released.val = true
    }
    @strategy.close_task_execution(run, execution)
    assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
    assert_true(
      @strategy.refresh_task_execution_cleanup(foreign, execution)
      is Err(ForeignOwner),
    )
    if mode >= 2 {
      assert_false(
        @strategy.refresh_task_execution_cleanup(run, execution).unwrap(),
      )
      assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
      @strategy.settle_task_execution(run, execution, false).unwrap()
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        reserved,
      )
      @strategy.settle_task_execution(run, execution, true).unwrap()
    }
    let stopped = @resources.ledger_usage(ledger)
    assert_eq(stopped.reserved_execution_bytes, 0L)
    assert_eq(stopped.transferred_bytes, 7L)
    if mode != 3 {
      assert_eq(
        stopped.held_bytes + stopped.reserved_retention_bytes,
        if mode == 0 {
          reserved - 100L + 10L
        } else {
          reserved
        },
      )
      assert_false(
        @strategy.refresh_task_execution_cleanup(run, execution).unwrap(),
      )
      assert_eq(@resources.ledger_usage(ledger), stopped)
      storage_released.val = true
      assert_true(
        @strategy.refresh_task_execution_cleanup(run, execution).unwrap(),
      )
    }
    let cleaned = @resources.ledger_usage(ledger)
    assert_eq(cleaned.held_bytes, 0L)
    assert_eq(cleaned.reserved_retention_bytes, 0L)
    assert_eq(cleaned.transferred_bytes, 7L)
    assert_true(
      @strategy.refresh_task_execution_cleanup(run, execution).unwrap(),
    )
    assert_eq(@resources.ledger_usage(ledger), cleaned)
  }
}
