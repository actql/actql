///|
#borrow(ledger)
extern "C" fn probe_begin(ledger : @resources.Ledger) -> Unit = "actql_test_capacity_probe_begin"

///|
extern "C" fn probe_end() -> Unit = "actql_test_capacity_probe_end"

///|
extern "C" fn probe_execution() -> Int64 = "actql_test_capacity_probe_execution"

///|
test "actual original Resource reduction updates diagnostic before later refusal" {
  let ledger = @resources.create_ledger({
    planning_work: 4,
    attempts: 4,
    holdings: 4,
    transfer_bytes: 1000L,
    retained_bytes: 1000L,
    execution_bytes: 1000L,
  }).unwrap()
  let token = @resources.reserve_attempt(ledger, 9L, 300L, 200L).unwrap()
  @resources.consume_reserved_attempt(ledger, token).unwrap()
  @resources.charge_transfer(ledger, token, 2L).unwrap()
  let holding = @resources.retain_allocation(ledger, token, 80L).unwrap()
  @resources.mark_cleanup_pending(ledger, token).unwrap()
  probe_begin(ledger)
  defer probe_end()
  let before = @resources.ledger_usage(ledger)
  @resources.reduce_execution_reservation_capacity(ledger, token, 120L, 60L).unwrap()
  assert_eq(probe_execution(), 60L)
  assert_eq(@resources.ledger_usage(ledger), {
    ..before,
    reserved_retention_bytes: 120L,
    reserved_execution_bytes: 60L,
  })
  assert_true(@resources.reservation_open(token))
  assert_true(@resources.reservation_pending(token))
  assert_true(
    @resources.reserve_attempt(ledger, 0L, 0L, 941L)
    is Err(@resources.ExecutionLimit),
  )
  assert_eq(probe_execution(), 60L)
  assert_eq(
    @resources.reduce_execution_reservation_capacity(ledger, token, 120L, 61L),
    Err(@resources.InvalidCharge),
  )
  assert_eq(probe_execution(), 60L)
  @resources.settle_reservation(ledger, token).unwrap()
  @resources.release_allocation(ledger, holding).unwrap()
  assert_eq(probe_execution(), 0L)
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.live_reservations, 0)
  assert_eq(closed.holdings, 0)
  assert_eq(closed.attempts, 1)
  assert_eq(closed.transferred_bytes, 2L)
}
