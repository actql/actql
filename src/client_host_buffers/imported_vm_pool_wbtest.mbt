///|
// Private capacity stand-ins. No child VM, provider, channel, FD or numerical
// profile is established by this portable accounting counter.
test "imported VM pool does not reserve the same fixed memory twice" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 4,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 32L,
  }).unwrap()
  let vm = @resources.reserve_shared_capacity(ledger, 16L).unwrap()
  let host = @resources.reserve_shared_capacity(ledger, 16L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let pool = open_pool_on_ledger(ledger, 12L, 4, 6).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  let slot = reserve_output_buffer(pool, 4, 0L, () => true).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 8L)
  assert_eq(@resources.shared_capacity_usage(vm).allocated, 8L)
  assert_eq(@resources.shared_capacity_usage(host).allocated, 0L)
  close_buffer(pool, slot).unwrap()
  close_pool(pool).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(@resources.shared_capacity_usage(vm).closing)
  assert_false(@resources.shared_capacity_usage(host).closing)
}
