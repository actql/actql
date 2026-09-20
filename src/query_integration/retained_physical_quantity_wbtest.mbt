///|
test "retained representation settles physical bytes without changing logical identity" {
  // Trusted Store fixtures simulate verified compact and expanded encodings.
  // This tests common admission/settlement, not a native file codec.
  for bytes in [4L, 10L, 80L, 100L, 101L] {
    let (run, _) = captured_graph_fixture()
    let ledger = @strategy.captured_dag_ledger(run)
    let released = Ref(false)
    let transport : FixedComputeTestTransport = { settled: None, }
    let task = captured_graph_duckdb_try_start(
      run,
      1,
      transport,
      retained_storage=(100L, fn() { released.val }),
    ).unwrap()
    let execution = @duckdb_driver.captured_duckdb_execution(task)
    let attempt = @duckdb_driver.captured_duckdb_attempt(task)
    let reserved = @resources.ledger_usage(ledger).reserved_retention_bytes
    let held = receive_retained_attempt(attempt, Ref(true), storage_bytes=bytes)
    let material = @execution.retained_output_material(held)
    @duckdb_compute.stage_retained_duckdb_compute_material(attempt, material).unwrap()
    transport.settled = Some(attempt)
    assert_eq(
      @duckdb_compute.retained_duckdb_compute_bytes(attempt),
      Some(bytes),
    )
    @strategy.settle_task_execution(run, execution, true).unwrap()
    let completion = @duckdb_driver.complete_captured_duckdb_task(run, task)
    if bytes <= 100L {
      assert_true(completion is Ok(_))
      let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
      let evidence = @execution.retain_completion_evidence(output, 10, 10).unwrap()
      let descriptor = @execution.retained_completion_descriptor(evidence)
      assert_eq(descriptor.bytes, 10)
      // Independent canonical preimage, not the physical representation bytes.
      assert_eq(
        descriptor.rows_cid,
        "sha256:7a4b037facb8a43d18989c0530806d5c8a3f23afd0c4be6bb7f4a0d2bf31b8bb",
      )
      assert_eq(
        @resources.ledger_usage(ledger).held_bytes,
        reserved - 100L + bytes,
      )
    } else {
      assert_true(completion is Err(_))
      assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
      assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        reserved,
      )
    }
    @strategy.close_task_execution(run, execution)
    assert_false(
      @strategy.refresh_task_execution_cleanup(run, execution).unwrap(),
    )
    released.val = true
    assert_true(
      @strategy.refresh_task_execution_cleanup(run, execution).unwrap(),
    )
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  }
}
