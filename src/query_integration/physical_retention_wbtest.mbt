///|
test "shared capture allocation stays charged through both branches and completed descendants" {
  let (run, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 100L, 100L, 0L).unwrap()
  @resources.charge_transfer(ledger, reservation, 37L).unwrap()
  let holding = @resources.retain_allocation(ledger, reservation, 100L).unwrap()
  @strategy.retain_captured_task_allocation(run, 0, holding).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  assert_true(
    @strategy.retain_captured_task_allocation(run, 0, holding)
    is Err(InvalidCharge),
  )
  captured_graph_local(run, 1).unwrap()
  captured_graph_local(run, 2).unwrap()
  captured_graph_local(run, 3).unwrap()
  @strategy.close_captured_task_output(run, 0)
  assert_true(@strategy.captured_task_completed(run, 0))
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 23280100L)
  @strategy.close_captured_task_output(run, 1)
  @strategy.close_captured_task_output(run, 2)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 15520100L)
  assert_eq(
    @execution.completed_row_count(
      @strategy.captured_task_output(run, 3, Step(1)).unwrap(),
    ),
    1,
  )
  @strategy.close_captured_task_output(run, 3)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 37L)
}

///|
test "closing the captured root revokes prepared reads without closing independent results" {
  let (run, _) = captured_graph_fixture()
  captured_graph_local(run, 1).unwrap()
  let read = @strategy.captured_task_input(run, 2, 100, 10000).unwrap()
  assert_true(@execution.producer_read_available(read))
  @strategy.close_captured_task_output(run, 0)
  assert_false(@execution.producer_read_available(read))
  assert_true(@strategy.captured_task_input(run, 2, 100, 10000) is Err(_))
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is Some(_))
}

///|
test "closed capture stays held until an in-flight native consumer confirms cleanup" {
  let (run, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 0L, 100L, 0L).unwrap()
  let holding = @resources.retain_allocation(ledger, reservation, 100L).unwrap()
  @strategy.retain_captured_task_allocation(run, 0, holding).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  let transport : FixedComputeTestTransport = { settled: None, }
  let attempt = captured_graph_duckdb_start(run, 1, transport)
  @strategy.close_captured_task_output(run, 0)
  @strategy.stop_captured_dag(run)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 100L)
  @strategy.close_task_execution(
    run,
    @strategy.captured_duckdb_execution(attempt),
  )
  @strategy.settle_task_execution(
    run,
    @strategy.captured_duckdb_execution(attempt),
    true,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
}

///|
test "native settlement preserves post-DB scratch and cannot enlarge or erase pending capacity" {
  let ledger = @resources.create_ledger({
    planning_work: 10,
    attempts: 3,
    holdings: 2,
    transfer_bytes: 100L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let reservation = @resources.reserve_attempt(ledger, 100L, 40L, 100L).unwrap()
  @resources.charge_transfer(ledger, reservation, 9L).unwrap()
  @resources.mark_cleanup_pending(ledger, reservation).unwrap()
  let before = @resources.ledger_usage(ledger)
  for invalid in [-1L, 101L] {
    assert_true(
      @resources.settle_execution_reservation(
        ledger,
        reservation,
        remaining_execution=invalid,
      )
      is Err(InvalidCharge),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
  }
  @resources.settle_execution_reservation(
    ledger,
    reservation,
    remaining_execution=30L,
  ).unwrap()
  let pending = @resources.ledger_usage(ledger)
  assert_eq(pending.reserved_execution_bytes, 30L)
  assert_eq(pending.reserved_retention_bytes, 40L)
  assert_eq(pending.transferred_bytes, 9L)
  assert_eq(pending.reserved_transfer_bytes, 0L)
  assert_false(@resources.reservation_pending(reservation))
  assert_true(
    @resources.reserve_attempt(ledger, 0L, 0L, 71L) is Err(ExecutionLimit),
  )
  assert_true(
    @resources.settle_execution_reservation(
      ledger,
      reservation,
      remaining_execution=31L,
    )
    is Err(InvalidCharge),
  )
  assert_eq(@resources.ledger_usage(ledger), pending)
  @resources.settle_reservation(ledger, reservation).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 9L)
}

///|
test "native settlement keeps retention reserved until success or buffer disposal" {
  let ledger = @resources.create_ledger({
    planning_work: 10,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 100L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let reservation = @resources.reserve_attempt(ledger, 100L, 100L, 100L).unwrap()
  @resources.charge_transfer(ledger, reservation, 7L).unwrap()
  @resources.settle_execution_reservation(ledger, reservation).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.transferred_bytes, 7L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 100L)
  assert_true(
    @resources.reserve_attempt(ledger, 0L, 1L, 0L) is Err(RetentionLimit),
  )
  let holding = @resources.retain_allocation(ledger, reservation, 100L).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 100L)
  @resources.release_allocation(ledger, holding).unwrap()
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 7L)
}

///|
test "closed Local parent is retained by completed child until last result release" {
  let (run, _) = captured_graph_fixture()
  captured_graph_local(run, 1).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 7760000L)
  captured_graph_local(run, 2).unwrap()
  captured_graph_local(run, 3).unwrap()
  @strategy.close_captured_task_output(run, 1)
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 23280000L)
  assert_eq(
    @execution.completed_row_count(
      @strategy.captured_task_output(run, 3, Step(1)).unwrap(),
    ),
    1,
  )
  @strategy.close_captured_task_output(run, 3)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 7760000L)
  @strategy.close_captured_task_output(run, 2)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  @strategy.close_captured_task_output(run, 3)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(@strategy.next_captured_task(run) is None)
}

///|
test "closing a result revokes an already prepared downstream read without restarting checked tasks" {
  let (run, _) = captured_graph_fixture()
  // Closing an uncreated port cannot poison a later successful task.
  @strategy.close_captured_task_output(run, 1)
  captured_graph_local(run, 1).unwrap()
  captured_graph_local(run, 2).unwrap()
  let read = @strategy.captured_task_input(run, 3, 100, 10000).unwrap()
  assert_true(@execution.producer_read_available(read))
  @strategy.close_captured_task_output(run, 1)
  assert_false(@execution.producer_read_available(read))
  assert_true(@strategy.captured_task_input(run, 3, 100, 10000) is Err(_))
  assert_true(@strategy.captured_task_output(run, 2, Step(1)) is Some(_))
  assert_true(@strategy.next_captured_task(run) is None)
}

///|
test "cancelled native child retains its closed parent until cleanup confirmation" {
  let (run, _) = captured_graph_fixture()
  captured_graph_local(run, 1).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  captured_graph_local(run, 2).unwrap()
  let transport : FixedComputeTestTransport = { settled: None, }
  let attempt = captured_graph_duckdb_start(run, 3, transport)
  @strategy.close_captured_task_output(run, 1)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 15520000L)
  @strategy.stop_captured_dag(run)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 15520000L)
  @strategy.close_task_execution(
    run,
    @strategy.captured_duckdb_execution(attempt),
  )
  @strategy.settle_task_execution(
    run,
    @strategy.captured_duckdb_execution(attempt),
    true,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 7760000L)
  assert_true(@strategy.next_captured_task(run) is None)
  assert_true(@strategy.captured_task_output(run, 2, Step(1)) is Some(_))
  assert_true(@strategy.captured_task_output(run, 3, Step(1)) is None)
}
