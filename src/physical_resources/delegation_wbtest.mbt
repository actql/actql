///|
fn delegation_limits() -> LedgerLimits {
  {
    planning_work: 7,
    attempts: 3,
    holdings: 2,
    transfer_bytes: 20L,
    retained_bytes: 30L,
    execution_bytes: 40L,
  }
}

///|
fn delegation_parent() -> Ledger {
  create_ledger({ ..delegation_limits(), attempts: 4, }).unwrap()
}

///|
test "delegated holding slots cannot be consumed by an existing parent reservation" {
  let ledger = create_ledger({
    ..delegation_limits(),
    attempts: 5,
    retained_bytes: 31L,
  }).unwrap()
  let existing = reserve_attempt(ledger, 0L, 1L, 0L).unwrap()
  let child = reserve_execution_delegation(
    ledger,
    delegation_limits(),
    30L,
    40L,
  ).unwrap()
  assert_true(retain_allocation(ledger, existing, 1L) is Err(HoldingLimit))
  let unused = ledger_usage(create_ledger(delegation_limits()).unwrap())
  settle_execution_delegation(ledger, child, Some(unused)).unwrap()
  retain_allocation(ledger, existing, 1L).unwrap() |> ignore
}

///|
test "large cumulative checkpoints add deltas without integer wraparound" {
  let limits = {
    planning_work: 2147483647,
    attempts: 2147483646,
    holdings: 2147483647,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }
  let ledger = create_ledger({ ..limits, attempts: 2147483647, }).unwrap()
  let child = reserve_execution_delegation(ledger, limits, 0L, 0L).unwrap()
  let usage = {
    ..ledger_usage(create_ledger(limits).unwrap()),
    planning_work: 2000000000,
    attempts: 2000000000,
    holdings: 2000000000,
  }
  report_execution_delegation(ledger, child, usage).unwrap()
  report_execution_delegation(ledger, child, usage).unwrap()
  settle_execution_delegation(ledger, child, None).unwrap()
  assert_eq(ledger_usage(ledger).planning_work, 2147483647)
  assert_eq(ledger_usage(ledger).attempts, 2147483647)
  assert_eq(ledger_usage(ledger).holdings, 2147483647)
}

///|
test "delegated quotas exclude other work before child usage is reported" {
  let ledger = delegation_parent()
  let child = reserve_execution_delegation(
    ledger,
    delegation_limits(),
    30L,
    40L,
  ).unwrap()
  assert_eq(execution_delegation_limits(child), delegation_limits())
  assert_eq(ledger_admission_limits(ledger).attempts, 1)
  assert_eq(ledger_admission_limits(ledger).planning_work, 0)
  assert_eq(ledger_admission_limits(ledger).holdings, 0)
  assert_eq(charge_planning(ledger, 1), Err(PlanningLimit))
  assert_true(reserve_attempt(ledger, 0L, 0L, 0L) is Err(AttemptLimit))
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger_usage(ledger).reserved_transfer_bytes, 20L)
  let child_ledger = create_ledger(delegation_limits()).unwrap()
  settle_execution_delegation(ledger, child, Some(ledger_usage(child_ledger))).unwrap()
  charge_planning(ledger, 7).unwrap()
  let next = reserve_attempt(ledger, 20L, 30L, 40L).unwrap()
  retain_allocation(ledger, next, 30L).unwrap() |> ignore
  assert_eq(ledger_usage(ledger).attempts, 2)
  assert_true(
    settle_execution_delegation(ledger, child, None) is Err(ClosedReservation),
  )
}

///|
test "delegation preflight failure has no partial reservations or quota consumption" {
  for
    altered in [
      { ..delegation_limits(), planning_work: 8, },
      { ..delegation_limits(), attempts: 4, },
      { ..delegation_limits(), holdings: 3, },
      { ..delegation_limits(), transfer_bytes: 21L, },
      { ..delegation_limits(), retained_bytes: 31L, },
      { ..delegation_limits(), execution_bytes: 41L, },
    ] {
    let ledger = delegation_parent()
    let before = ledger_usage(ledger)
    assert_true(
      reserve_execution_delegation(ledger, altered, 30L, 40L) is Err(_),
    )
    assert_eq(ledger_usage(ledger), before)
    reserve_execution_delegation(ledger, delegation_limits(), 30L, 40L).unwrap()
    |> ignore
  }
}

///|
test "checkpoint usage is monotonic exact and unknown stop consumes remaining allowance" {
  let ledger = delegation_parent()
  let child = reserve_execution_delegation(
    ledger,
    delegation_limits(),
    30L,
    40L,
  ).unwrap()
  let child_ledger = create_ledger(delegation_limits()).unwrap()
  charge_planning(child_ledger, 2).unwrap()
  let reservation = reserve_attempt(child_ledger, 10L, 10L, 20L).unwrap()
  charge_transfer(child_ledger, reservation, 6L).unwrap()
  let holding = retain_allocation(child_ledger, reservation, 10L).unwrap()
  let usage = ledger_usage(child_ledger)
  report_execution_delegation(ledger, child, usage).unwrap()
  report_execution_delegation(ledger, child, usage).unwrap()
  assert_eq(ledger_usage(ledger).planning_work, 2)
  assert_eq(ledger_usage(ledger).attempts, 2)
  assert_eq(ledger_usage(ledger).transferred_bytes, 6L)
  assert_eq(ledger_usage(ledger).reserved_transfer_bytes, 14L)
  let before = ledger_usage(ledger)
  assert_eq(
    report_execution_delegation(ledger, child, { ..usage, attempts: 0, }),
    Err(InvalidCharge),
  )
  assert_eq(
    report_execution_delegation(ledger, child, {
      ..usage,
      transferred_bytes: 21L,
    }),
    Err(InvalidCharge),
  )
  assert_eq(
    report_execution_delegation(delegation_parent(), child, usage),
    Err(ForeignOwner),
  )
  assert_eq(ledger_usage(ledger), before)
  release_allocation(child_ledger, holding).unwrap()
  settle_reservation(child_ledger, reservation).unwrap()
  // A previous successful checkpoint is not an exact terminal report.
  settle_execution_delegation(ledger, child, None).unwrap()
  assert_eq(ledger_usage(ledger).planning_work, 7)
  assert_eq(ledger_usage(ledger).attempts, 4)
  assert_eq(ledger_usage(ledger).holdings, 2)
  assert_eq(ledger_usage(ledger).transferred_bytes, 6L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 14L)
  assert_eq(ledger_usage(ledger).reserved_transfer_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_true(reserve_attempt(ledger, 1L, 0L, 0L) is Err(AttemptLimit))
  assert_eq(charge_planning(ledger, 1), Err(PlanningLimit))
}

///|
test "exact terminal usage returns only unused quotas and keeps consumed work" {
  let ledger = delegation_parent()
  let child = reserve_execution_delegation(
    ledger,
    delegation_limits(),
    30L,
    40L,
  ).unwrap()
  let child_ledger = create_ledger(delegation_limits()).unwrap()
  let reservation = reserve_attempt(child_ledger, 20L, 0L, 0L).unwrap()
  charge_transfer(child_ledger, reservation, 5L).unwrap()
  settle_reservation(child_ledger, reservation).unwrap()
  settle_execution_delegation(ledger, child, Some(ledger_usage(child_ledger))).unwrap()
  assert_eq(ledger_usage(ledger).attempts, 2)
  assert_eq(ledger_usage(ledger).transferred_bytes, 5L)
  assert_true(reserve_attempt(ledger, 16L, 0L, 0L) is Err(TransferLimit))
  reserve_attempt(ledger, 15L, 0L, 0L).unwrap() |> ignore
}

///|
test "unknown transfer in a subledger remains uncertain after cumulative parent reporting" {
  let parent = create_ledger({ ..delegation_limits(), attempts: 5, }).unwrap()
  let outer = reserve_execution_delegation(
    parent,
    { ..delegation_limits(), attempts: 4, },
    30L,
    40L,
  ).unwrap()
  let child_ledger = delegation_parent()
  let inner = reserve_execution_delegation(
    child_ledger,
    delegation_limits(),
    30L,
    40L,
  ).unwrap()
  settle_execution_delegation(child_ledger, inner, None).unwrap()
  let usage = ledger_usage(child_ledger)
  report_execution_delegation(parent, outer, usage).unwrap()
  assert_eq(ledger_usage(parent).transferred_bytes, 0L)
  assert_eq(ledger_usage(parent).uncertain_transfer_bytes, 20L)
  let before = ledger_usage(parent)
  assert_eq(
    report_execution_delegation(parent, outer, {
      ..usage,
      uncertain_transfer_bytes: 19L,
    }),
    Err(InvalidCharge),
  )
  assert_eq(ledger_usage(parent), before)
  settle_execution_delegation(parent, outer, Some(usage)).unwrap()
  assert_eq(ledger_usage(parent).uncertain_transfer_bytes, 20L)
}
