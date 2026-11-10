///|
test "saved file application holds completed ACK bytes not future page maxima" {
  let physical = @execution.execution_capacity(1024L, 2048L).unwrap()
  let first = saved_effect_file_application_capacity(2, physical, 0L).unwrap()
  let next = saved_effect_file_application_capacity(2, physical, 37L).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(next) -
    @execution.execution_capacity_retained_bytes(first),
    37L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(next) -
    @execution.execution_capacity_execution_bytes(first),
    37L,
  )
  let slots = saved_effect_file_application_capacity(100, physical, 37L).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(slots) -
    @execution.execution_capacity_retained_bytes(next) <
    100000L,
  )
  assert_true(saved_effect_file_application_capacity(-1, physical, 0L) is None)
  assert_true(saved_effect_file_application_capacity(1, physical, -1L) is None)
}

///|
test "saved application preserves restoration and scratch before entered backing" {
  let original = @execution.execution_capacity(249862830L, 337566898L).unwrap()
  let phase = @execution.execution_capacity(4956488L, 4956488L).unwrap()
  let next = saved_effect_file_next_phase_capacity(original, phase).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(next), 254819318L)
  assert_eq(@execution.execution_capacity_execution_bytes(next), 337566898L)
  let larger = saved_effect_file_next_phase_capacity(
    original,
    @execution.execution_capacity(5000000L, 100000000L).unwrap(),
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(larger), 254862830L)
  assert_eq(@execution.execution_capacity_execution_bytes(larger), 349862830L)
}

///|
test "saved target transfer shares funded working bytes and retains consumed history" {
  let ledger = @initial_resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 8L,
    retained_bytes: 8L,
    execution_bytes: 8L,
  }).unwrap()
  // The SAME entry already owns all working bytes before this IO attempt.
  let working = @initial_resources.reserve_capacity(ledger, 8L, 8L).unwrap()
  let before = @initial_resources.ledger_usage(ledger)
  let io = saved_effect_file_reserve_transfer(ledger, 4).unwrap()
  let reserved = @initial_resources.ledger_usage(ledger)
  assert_eq(reserved.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(reserved.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(reserved.reserved_transfer_bytes, 8L)
  @initial_resources.consume_reserved_attempt(ledger, io).unwrap()
  @initial_resources.charge_transfer(ledger, io, 3L).unwrap()
  @initial_resources.mark_transfer_uncertain(ledger, io, 2L).unwrap()
  @initial_resources.settle_reservation(ledger, io).unwrap()
  let completed = @initial_resources.ledger_usage(ledger)
  assert_eq(completed.attempts, 1)
  assert_eq(completed.transferred_bytes, 3L)
  assert_eq(completed.uncertain_transfer_bytes, 2L)
  assert_eq(completed.reserved_transfer_bytes, 0L)
  assert_true(
    saved_effect_file_reserve_transfer(ledger, 4) is Err(AttemptLimit),
  )
  assert_eq(@initial_resources.ledger_usage(ledger), completed)
  assert_true(
    @initial_resources.capacity_reservation_matches(ledger, working, 8L, 8L),
  )
}
