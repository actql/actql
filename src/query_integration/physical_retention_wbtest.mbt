///|
test "captured external holding waits for physical release in either close order" {
  for release_first in [false, true] {
    let (run, _) = captured_graph_fixture()
    let ledger = @strategy.captured_dag_ledger(run)
    let reservation = @resources.reserve_attempt(ledger, 100L, 100L, 0L).unwrap()
    @resources.charge_transfer(ledger, reservation, 37L).unwrap()
    let holding = @resources.retain_allocation(ledger, reservation, 100L).unwrap()
    let released = Ref(release_first)
    @strategy.retain_captured_task_allocation(run, 0, holding, release_confirmed=fn() {
      released.val
    }).unwrap()
    @resources.settle_reservation(ledger, reservation).unwrap()
    // A duplicate attachment cannot replace a pending check with unconditional
    // success, even when it carries the original ledger-owned token.
    assert_true(
      @strategy.retain_captured_task_allocation(run, 0, holding)
      is Err(InvalidCharge),
    )
    @strategy.refresh_captured_retention(run)
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 100L)
    let read = @strategy.captured_task_input(run, 1, 100, 10000).unwrap()
    @strategy.close_captured_task_output(run, 0)
    assert_false(@execution.producer_read_available(read))
    @strategy.refresh_captured_retention(run)
    assert_eq(
      @resources.ledger_usage(ledger).held_bytes,
      if release_first {
        0L
      } else {
        100L
      },
    )
    released.val = true
    @strategy.refresh_captured_retention(run)
    @strategy.refresh_captured_retention(run)
    @strategy.close_captured_task_output(run, 0)
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 37L)
    assert_false(@execution.producer_read_available(read))
  }
}

///|
test "captured output pin keeps one completed allocation after port close" {
  let (run, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  captured_graph_local(run, 1).unwrap()
  let held = @resources.ledger_usage(ledger).held_bytes
  assert_true(held > 0L)
  assert_true(@strategy.pin_captured_task_output(run, 1, Step(0), 1) is Err(_))
  let pin = @strategy.pin_captured_task_output(run, 1, Step(1), 1).unwrap()
  assert_true(@strategy.pin_captured_task_output(run, 1, Step(1), 1) is Err(_))
  let borrowed = @strategy.captured_output_pin_materialized(pin)
  assert_true(@execution.completed_output_available(borrowed))
  @strategy.close_captured_task_output(run, 0)
  @strategy.close_captured_task_output(run, 1)
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
  assert_true(@strategy.pin_captured_task_output(run, 1, Step(1), 1) is Err(_))
  assert_true(@execution.completed_output_available(borrowed))
  assert_eq(@resources.ledger_usage(ledger).held_bytes, held)
  assert_true(@strategy.release_captured_output_pin(pin))
  assert_false(@execution.completed_output_available(borrowed))
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_false(@strategy.release_captured_output_pin(pin))
}

///|
test "captured output waits for every independent consumer pin" {
  let (run, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  captured_graph_local(run, 1).unwrap()
  let first = @strategy.pin_captured_task_output(run, 1, Step(1), 2).unwrap()
  let second = @strategy.pin_captured_task_output(run, 1, Step(1), 2).unwrap()
  let second_view = @strategy.captured_output_pin_materialized(second)
  @strategy.close_captured_task_output(run, 0)
  @strategy.close_captured_task_output(run, 1)
  assert_true(@strategy.release_captured_output_pin(first))
  assert_true(@execution.completed_output_available(second_view))
  assert_true(@resources.ledger_usage(ledger).held_bytes > 0L)
  assert_true(@strategy.release_captured_output_pin(second))
  assert_false(@execution.completed_output_available(second_view))
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
}

///|
test "checked Result pin rejects a foreign owner and retains its exact output" {
  let (run, issuer) = captured_graph_fixture()
  let graph = @strategy.captured_dag_graph(run)
  let (foreign, foreign_issuer) = captured_graph_fixture()
  let foreign_graph = @strategy.captured_dag_graph(foreign)
  for task in 1..<@strategy.graph_task_count(graph) {
    captured_graph_local(run, task).unwrap()
  }
  let task = @strategy.graph_result_task(graph, 0).unwrap()
  let occurrence = @strategy.graph_result_occurrence(graph, 0).unwrap()
  let foreign_occurrence = @strategy.graph_result_occurrence(foreign_graph, 0).unwrap()
  assert_true(
    @strategy.pin_captured_result_output(run, task, foreign_occurrence, 1)
    is Err(ForeignCandidate),
  )
  assert_true(
    @strategy.pin_captured_result_output(run, 0, occurrence, 1)
    is Err(ForeignCandidate),
  )
  let pin = @strategy.pin_captured_result_output(run, task, occurrence, 1).unwrap()
  let borrowed = @strategy.captured_output_pin_materialized(pin)
  assert_true(@execution.completed_output_available(borrowed))
  @mock.close_mock_query_issuer(issuer)
  for index in 0..<@strategy.graph_task_count(graph) {
    @strategy.close_captured_task_output(run, index)
  }
  assert_true(@execution.completed_output_available(borrowed))
  assert_true(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes > 0L,
  )
  assert_true(@strategy.release_captured_output_pin(pin))
  assert_false(@execution.completed_output_available(borrowed))
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
    0L,
  )
  @mock.close_mock_query_issuer(foreign_issuer)
  @strategy.stop_captured_dag(foreign)
  @strategy.close_captured_task_output(foreign, 0)
}

///|
test "capture cleanup confirmation does not erase completed child retention" {
  let (run, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 0L, 100L, 0L).unwrap()
  let holding = @resources.retain_allocation(ledger, reservation, 100L).unwrap()
  let released = Ref(false)
  @strategy.retain_captured_task_allocation(run, 0, holding, release_confirmed=fn() {
    released.val
  }).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  captured_graph_local(run, 1).unwrap()
  @strategy.close_captured_task_output(run, 0)
  released.val = true
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 7760100L)
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is Some(_))
  @strategy.close_captured_task_output(run, 1)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
}

///|
test "capture storage release and native consumer stop are separate confirmations" {
  for storage_first in [false, true] {
    let (run, _) = captured_graph_fixture()
    let ledger = @strategy.captured_dag_ledger(run)
    let reservation = @resources.reserve_attempt(ledger, 0L, 100L, 0L).unwrap()
    let holding = @resources.retain_allocation(ledger, reservation, 100L).unwrap()
    let released = Ref(false)
    @strategy.retain_captured_task_allocation(run, 0, holding, release_confirmed=fn() {
      released.val
    }).unwrap()
    @resources.settle_reservation(ledger, reservation).unwrap()
    let transport : FixedComputeTestTransport = { settled: None, }
    let attempt = captured_graph_duckdb_start(run, 1, transport)
    let execution = @duckdb_driver.captured_duckdb_execution(attempt)
    @strategy.close_captured_task_output(run, 0)
    @strategy.stop_captured_dag(run)
    @strategy.close_task_execution(run, execution)
    if storage_first {
      released.val = true
    } else {
      @strategy.settle_task_execution(run, execution, true).unwrap()
    }
    @strategy.refresh_captured_retention(run)
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 100L)
    released.val = true
    if storage_first {
      @strategy.settle_task_execution(run, execution, true).unwrap()
    }
    @strategy.refresh_captured_retention(run)
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
    assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
  }
}

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
    @duckdb_driver.captured_duckdb_execution(attempt),
  )
  @strategy.settle_task_execution(
    run,
    @duckdb_driver.captured_duckdb_execution(attempt),
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
    @duckdb_driver.captured_duckdb_execution(attempt),
  )
  @strategy.settle_task_execution(
    run,
    @duckdb_driver.captured_duckdb_execution(attempt),
    true,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 7760000L)
  assert_true(@strategy.next_captured_task(run) is None)
  assert_true(@strategy.captured_task_output(run, 2, Step(1)) is Some(_))
  assert_true(@strategy.captured_task_output(run, 3, Step(1)) is None)
}
