///|
test "resident provision freezes dispatch and search until binding or close" {
  let (run, _issuer) = captured_graph_fixture()
  let (foreign, _other) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 10000,
    max_revisions: 3,
  }).unwrap()
  let offers = search_offers(run, registry, [1, 2, 3], Some(1L))
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None).unwrap()
    is Selected(_),
  )
  assert_true(
    @strategy.begin_resident_environment(run, 1, 100L) is Err(ForeignCandidate),
  )
  let profile = @strategy.prepare_resident_profile(
    run,
    100L,
    Some(0L),
    Some(0L),
    Array::make(4, @strategy.ResidentImportEstimate::{
      milliseconds: Some(0L),
      transfer_bytes: 20L,
      scratch_bytes: 100L,
      table_bytes: 80L,
    }),
  ).unwrap()
  // A separate run below exercises the selected resident profile. Merely
  // changing a rejected request must not reset an already accepted search.
  let (run, _issuer2) = captured_graph_fixture()
  assert_false(@strategy.resident_profile_matches(run, profile))
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 10000,
    max_revisions: 3,
  }).unwrap()
  let profile = @strategy.prepare_resident_profile(
    run,
    1000L,
    Some(0L),
    Some(0L),
    Array::make(4, @strategy.ResidentImportEstimate::{
      milliseconds: Some(0L),
      transfer_bytes: 20L,
      scratch_bytes: 100L,
      table_bytes: 80L,
    }),
  ).unwrap()
  let offers = search_offers(run, registry, [1, 2, 3], Some(1L))
  for task in 1..<4 {
    let base = @strategy.prepare_task_offer(
      run,
      task,
      @planning.capability_registration_at(registry, 1).unwrap(),
      1,
      [{ work_slots: [0], milliseconds: Some(1L), }],
      { transfer_bytes: 100L, retained_bytes: 100L, execution_bytes: 2000L, },
      100,
    ).unwrap()
    offers[task * 2 - 1] = @strategy.resident_task_offer(run, base, profile).unwrap()
  }
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None).unwrap()
    is Selected(_),
  )
  assert_true(
    @strategy.begin_resident_environment(run, 1, 999L)
    is Err(Physical(InvalidCharge)),
  )
  let ledger = @strategy.captured_dag_ledger(run)
  let before = @resources.ledger_usage(ledger)
  let env = @strategy.begin_resident_environment(run, 1, 1000L).unwrap()
  assert_eq(@strategy.next_captured_task(run), None)
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None) is Err(Busy),
  )
  assert_true(
    @strategy.confirm_resident_environment(foreign, env, 100L)
    is Err(ForeignCandidate),
  )
  assert_true(
    @strategy.confirm_resident_environment(run, env, 99L)
    is Err(Physical(InvalidCharge)),
  )
  assert_false(@strategy.resident_environment_available(run, env))
  @strategy.confirm_resident_environment(run, env, 1000L).unwrap()
  assert_true(@strategy.resident_environment_available(run, env))
  assert_eq(@strategy.next_captured_task(run), Some(1))
  assert_true(
    @strategy.prepare_resident_table(run, env, 0, 79L, 1000, 10000, 10000)
    is Err(Physical(InvalidCharge)),
  )
  // Unstarted preparations are reversible, including an actual ledger refusal.
  // More than the holding/name bound: names and table quota must not leak.
  let planned = @resources.ledger_usage(ledger).planning_work
  let blocker = @resources.reserve_attempt(ledger, 300000L, 0L, 0L).unwrap()
  let attempts_before_corrections = @resources.ledger_usage(ledger).attempts
  let mut stale = None
  for _ in 0..<20 {
    let pending = @strategy.prepare_resident_table(
      run, env, 0, 80L, 1000, 10000, 10000,
    ).unwrap()
    assert_true(
      @strategy.cancel_resident_table_preparation(foreign, pending)
      is Err(ForeignOwner),
    )
    assert_true(
      @strategy.begin_resident_transfer(run, pending, 20L, 100L)
      is Err(Physical(TransferLimit)),
    )
    @strategy.cancel_resident_table_preparation(run, pending).unwrap()
    assert_true(
      @strategy.cancel_resident_table_preparation(run, pending)
      is Err(ForeignOwner),
    )
    stale = Some(pending)
  }
  assert_eq(
    @resources.ledger_usage(ledger).attempts,
    attempts_before_corrections,
  )
  assert_true(@resources.ledger_usage(ledger).planning_work > planned)
  @resources.settle_reservation(ledger, blocker).unwrap()
  let table = @strategy.prepare_resident_table(
    run, env, 0, 80L, 1000, 10000, 10000,
  ).unwrap()
  assert_true(
    @strategy.borrow_resident_table(run, table, 1, 1000, 10000, 10000)
    is Err(ForeignCandidate),
  )
  let attempts = @resources.ledger_usage(ledger).attempts
  assert_true(
    @strategy.begin_resident_transfer(run, table, 21L, 100L)
    is Err(Physical(InvalidCharge)),
  )
  assert_true(
    @strategy.begin_resident_transfer(run, table, 20L, 101L)
    is Err(Physical(InvalidCharge)),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, attempts)
  let transfer = @strategy.begin_resident_transfer(run, table, 20L, 100L).unwrap()
  assert_true(
    @strategy.cancel_resident_table_preparation(run, table)
    is Err(InvalidCharge),
  )
  assert_true(
    @strategy.begin_resident_transfer(run, stale.unwrap(), 20L, 100L)
    is Err(ForeignCandidate),
  )
  assert_eq(@strategy.next_captured_task(run), None)
  assert_true(
    @strategy.complete_resident_transfer(run, transfer) is Err(NotReady),
  )
  @strategy.charge_resident_transfer(run, transfer, 12L).unwrap()
  @strategy.settle_resident_transfer(run, transfer, false).unwrap()
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None) is Err(Busy),
  )
  @strategy.settle_resident_transfer(run, transfer, true).unwrap()
  @strategy.complete_resident_transfer(run, transfer).unwrap()
  assert_true(
    @strategy.abort_resident_transfer(run, transfer) is Err(ForeignCandidate),
  )
  assert_true(
    @strategy.begin_resident_transfer(run, table, 20L, 100L)
    is Err(ForeignCandidate),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 12L)
  let read = @strategy.borrow_resident_table(run, table, 1, 1000, 10000, 10000).unwrap()
  let another = @strategy.borrow_resident_table(
    run, table, 1, 1000, 10000, 10000,
  ).unwrap()
  let input = @strategy.captured_task_input(run, 1, 1000, 10000).unwrap()
  assert_true(@strategy.resident_read_matches(run, read, input))
  assert_false(@strategy.resident_read_matches(foreign, read, input))
  @strategy.retire_resident_table(run, table).unwrap()
  assert_false(@strategy.resident_read_matches(run, read, input))
  assert_true(
    @strategy.release_resident_table(run, table) is Err(InvalidCharge),
  )
  @strategy.return_resident_read(read).unwrap()
  assert_true(
    @strategy.release_resident_table(run, table) is Err(InvalidCharge),
  )
  @strategy.return_resident_read(another).unwrap()
  assert_true(@strategy.return_resident_read(another) is Err(InvalidCharge))
  @strategy.release_resident_table(run, table).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    before.reserved_execution_bytes + 1000L,
  )
  @strategy.close_resident_environment(run, env).unwrap()
  assert_false(@strategy.resident_environment_available(run, env))
  assert_true(@strategy.captured_dag_strategy(run) is None)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    before.reserved_execution_bytes + 1000L,
  )
  @strategy.settle_resident_environment(run, env).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    before.reserved_execution_bytes,
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts + 3)
  // Correction is possible after genuine environment loss, with the history
  // and planning work intact. There is no implicit retry of a started task.
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None).unwrap()
    is Selected(_),
  )
  let failed_provision = @strategy.begin_resident_environment(run, 1, 1000L).unwrap()
  @strategy.close_resident_environment(run, failed_provision).unwrap()
  assert_eq(@strategy.next_captured_task(run), None)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 1000L)
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None) is Err(Stopped),
  )
  @strategy.settle_resident_environment(run, failed_provision).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None) is Err(Stopped),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 12L)
}

///|
test "aborted resident import cannot publish after cleanup or reopen dispatch" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 3,
    max_strategies: 1,
    max_work: 1000,
    max_revisions: 2,
  }).unwrap()
  let profile = @strategy.prepare_resident_profile(
    run,
    1000L,
    Some(0L),
    Some(0L),
    Array::make(4, @strategy.ResidentImportEstimate::{
      milliseconds: Some(0L),
      transfer_bytes: 20L,
      scratch_bytes: 100L,
      table_bytes: 80L,
    }),
  ).unwrap()
  let offers = []
  for task in 1..<4 {
    let offer = @strategy.prepare_task_offer(
      run,
      task,
      @planning.capability_registration_at(registry, 1).unwrap(),
      1,
      [{ work_slots: [0], milliseconds: Some(1L), }],
      { transfer_bytes: 100L, retained_bytes: 100L, execution_bytes: 2000L, },
      100,
    ).unwrap()
    offers.push(@strategy.resident_task_offer(run, offer, profile).unwrap())
  }
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None).unwrap()
    is Selected(_),
  )
  let env = @strategy.begin_resident_environment(run, 1, 1000L).unwrap()
  @strategy.confirm_resident_environment(run, env, 1000L).unwrap()
  let table = @strategy.prepare_resident_table(
    run, env, 0, 80L, 1000, 10000, 10000,
  ).unwrap()
  let transfer = @strategy.begin_resident_transfer(run, table, 20L, 100L).unwrap()
  @strategy.charge_resident_transfer(run, transfer, 12L).unwrap()
  @strategy.abort_resident_transfer(run, transfer).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 1100L)
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None) is Err(Stopped),
  )
  @strategy.settle_resident_transfer(run, transfer, true).unwrap()
  assert_true(
    @strategy.complete_resident_transfer(run, transfer) is Err(Stopped),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 1000L)
  @strategy.close_resident_environment(run, env).unwrap()
  @strategy.settle_resident_environment(run, env).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 12L)
  assert_eq(@strategy.next_captured_task(run), None)
}
