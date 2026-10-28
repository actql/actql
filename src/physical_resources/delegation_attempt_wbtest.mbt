///|
test "delegation provisioning consumes only the current original attempt once" {
  let ledger = delegation_parent()
  let foreign = delegation_parent()
  let child = reserve_execution_delegation(
    ledger,
    delegation_limits(),
    30L,
    40L,
  ).unwrap()
  let reserved = ledger_usage(ledger)
  assert_eq(reserved.attempts, 0)
  assert_eq(reserved.reserved_attempts, 1)
  assert_eq(
    consume_execution_delegation_attempt(foreign, child),
    Err(ForeignOwner),
  )
  assert_eq(ledger_usage(ledger), reserved)
  consume_execution_delegation_attempt(ledger, child).unwrap()
  let entered = ledger_usage(ledger)
  assert_eq(entered.attempts, 1)
  assert_eq(entered.reserved_attempts, 0)
  assert_eq(entered.reserved_execution_bytes, 40L)
  consume_execution_delegation_attempt(ledger, child).unwrap()
  assert_eq(ledger_usage(ledger), entered)
  let unused = ledger_usage(create_ledger(delegation_limits()).unwrap())
  settle_execution_delegation(ledger, child, Some(unused)).unwrap()
  let stopped = ledger_usage(ledger)
  assert_eq(stopped.attempts, 1)
  assert_eq(stopped.reserved_execution_bytes, 0L)
  assert_eq(
    consume_execution_delegation_attempt(ledger, child),
    Err(ClosedReservation),
  )
  assert_eq(ledger_usage(ledger), stopped)
}

///|
test "never invoked delegated provisioning returns only its unused attempt" {
  let ledger = delegation_parent()
  let child = reserve_execution_delegation(
    ledger,
    delegation_limits(),
    30L,
    40L,
  ).unwrap()
  let unused = ledger_usage(create_ledger(delegation_limits()).unwrap())
  settle_execution_delegation(ledger, child, Some(unused)).unwrap()
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_eq(ledger_usage(ledger).reserved_attempts, 0)
  assert_eq(ledger_usage(ledger).live_delegations, 0)
}
