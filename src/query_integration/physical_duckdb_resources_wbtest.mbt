///|
test "common native start enforces calculated capacity against selected envelope" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let host = adaptive_host(run, registry)
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 1,
  }).unwrap()
  let offers = search_offers(run, registry, [1, 2, 3], Some(1L))
  @strategy.revise_strategy(
    run,
    [offers[1], offers[3], offers[5]],
    registry,
    None,
  ).unwrap()
  |> ignore
  let dispatch = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
  let setup = @dbhost.take_native_dispatch(dispatch).unwrap()
  let before = @strategy.ledger_usage(@strategy.captured_dag_ledger(run))
  // The offered 100-byte retention is below the concrete completion capacity.
  assert_true(
    @dbhost.start_configured_strategy_compute_host(
      setup,
      _ => false,
      100000L,
      1000000L,
    )
    is Err(Physical(InvalidCharge)),
  )
  assert_eq(@strategy.ledger_usage(@strategy.captured_dag_ledger(run)), before)
  assert_false(@strategy.captured_task_completed(run, 1))
}

///|
test "common DuckDB start cannot borrow external or exhausted reservations" {
  let (run, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  let reserved = @strategy.reserve_attempt(
    ledger, 300000L, 32000000L, 134217728L,
  ).unwrap()
  let before = @strategy.ledger_usage(ledger)
  let transport : FixedComputeTestTransport = { settled: None, }
  assert_true(
    captured_graph_duckdb_try_start(run, 1, transport)
    is Err(Physical(TransferLimit)),
  )
  assert_eq(@strategy.ledger_usage(ledger), before)
  assert_false(@strategy.captured_task_completed(run, 1))
  @strategy.settle_reservation(ledger, reserved).unwrap()
  for (transfer, execution) in [(0L, 1L), (1L, 0L), (-1L, 1L)] {
    assert_true(
      captured_graph_duckdb_try_start(
        run,
        1,
        transport,
        transfer_bytes=transfer,
        execution_bytes=execution,
      )
      is Err(Physical(InvalidLimits)),
    )
  }
  let attempt = captured_graph_duckdb_start(run, 1, transport)
  assert_eq(@strategy.ledger_usage(ledger).attempts, before.attempts + 1)
  assert_true(@strategy.ledger_usage(ledger).reserved_retention_bytes > 0L)
  // A fresh reservation is private to this exact attempt, never supplied by the
  // caller. Neither a foreign DAG nor an unrelated attempt can operate on it.
  let (other_run, _) = captured_graph_fixture()
  assert_true(
    @strategy.charge_captured_duckdb_transfer(other_run, attempt, 1L)
    is Err(ForeignOwner),
  )
  assert_true(
    @strategy.settle_captured_duckdb_native(other_run, attempt, true)
    is Err(ForeignOwner),
  )
  @strategy.charge_captured_duckdb_transfer(run, attempt, 7L).unwrap()
  captured_graph_duckdb_receive(attempt, 1)
  transport.settled = Some(attempt)
  assert_true(
    @strategy.complete_captured_duckdb_task(run, attempt)
    is Err(Physical(InvalidCharge)),
  )
  assert_false(@strategy.captured_task_completed(run, 1))
  @strategy.settle_captured_duckdb_native(run, attempt, true).unwrap()
  let before_complete = @strategy.ledger_usage(ledger)
  assert_true(before_complete.reserved_execution_bytes > 0L)
  @strategy.complete_captured_duckdb_task(run, attempt).unwrap()
  let complete = @strategy.ledger_usage(ledger)
  assert_eq(complete.holdings, before_complete.holdings + 1)
  assert_eq(complete.held_bytes, before_complete.reserved_retention_bytes)
  assert_eq(complete.reserved_retention_bytes, 0L)
  assert_eq(complete.reserved_execution_bytes, 0L)
  assert_eq(complete.transferred_bytes, 7L)
  assert_true(
    @strategy.charge_captured_duckdb_transfer(run, attempt, 1L)
    is Err(ClosedReservation),
  )
  // Starting B must acquire a new reservation, not reuse A's settled capacity.
  let b = captured_graph_duckdb_start(run, 2, { settled: None, })
  assert_eq(@strategy.ledger_usage(ledger).attempts, complete.attempts + 1)
  assert_true(
    @strategy.complete_captured_duckdb_task(run, attempt)
    is Err(ForeignCandidate),
  )
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_duckdb_task(run, b)
  @strategy.settle_captured_duckdb_native(run, b, true).unwrap()
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is Some(_))
  @strategy.close_captured_duckdb_task(run, attempt)
  assert_eq(@strategy.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@strategy.ledger_usage(ledger).transferred_bytes, 7L)
}

///|
test "common native cancellation and failed completion preserve staged cleanup accounting" {
  for failed_completion in [false, true] {
    let (run, _) = captured_graph_fixture()
    let ledger = @strategy.captured_dag_ledger(run)
    let attempt = captured_graph_duckdb_start(run, 1, { settled: None, })
    @strategy.charge_captured_duckdb_transfer(run, attempt, 9L).unwrap()
    let active = @strategy.ledger_usage(ledger)
    if failed_completion {
      @strategy.settle_captured_duckdb_native(run, attempt, true).unwrap()
      assert_true(
        @strategy.complete_captured_duckdb_task(run, attempt) is Err(DuckDB(_)),
      )
      assert_true(@strategy.ledger_usage(ledger).held_bytes > 0L)
      assert_true(@strategy.ledger_usage(ledger).reserved_execution_bytes > 0L)
    } else {
      @strategy.stop_captured_dag(run)
      @strategy.settle_captured_duckdb_native(run, attempt, false).unwrap()
      @strategy.close_captured_duckdb_task(run, attempt)
      assert_eq(@strategy.ledger_usage(ledger), active)
      @strategy.settle_captured_duckdb_native(run, attempt, true).unwrap()
    }
    @strategy.close_captured_duckdb_task(run, attempt)
    let final_usage = @strategy.ledger_usage(ledger)
    assert_eq(final_usage.reserved_execution_bytes, 0L)
    assert_eq(final_usage.reserved_retention_bytes, 0L)
    assert_eq(final_usage.held_bytes, 0L)
    assert_eq(final_usage.transferred_bytes, 9L)
    assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
  }
}
