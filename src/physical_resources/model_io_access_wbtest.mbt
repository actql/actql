///|
// Retirement in these vectors is a Model ACK double, not actual physical I/O.
test "erased Model access preserves the original installation and ticket bindings" {
  let installation = Ref(0)
  let shared = issue_model_io_admission(installation, 2, 2).unwrap()
  assert_true(issue_model_io_access(shared, Ref(0)) is Err(ForeignInstallation))
  let access = issue_model_io_access(shared, installation).unwrap()
  assert_true(
    issue_model_io_access(shared, installation) is Err(DuplicateAccess),
  )
  let other = issue_model_io_access(
    issue_model_io_admission(installation, 2, 2).unwrap(),
    installation,
  ).unwrap()
  let (ledger, _, reservation) = model_io_test_run()
  let (foreign, _, foreign_reservation) = model_io_test_run()
  let lease = claim_model_io_access(access, ledger, reservation, 0, 1).unwrap()
  for
    (owner, run, attempt, slot, serial) in [
      (other, ledger, reservation, 0, 1),
      (access, foreign, reservation, 0, 1),
      (access, ledger, foreign_reservation, 0, 1),
      (access, ledger, reservation, 1, 1),
      (access, ledger, reservation, 0, 2),
    ] {
    assert_true(
      settle_model_io_lease_after_owner_ack(
        owner, lease, run, attempt, slot, serial,
      )
      is Err(ForeignTicket),
    )
    assert_eq(model_io_admission_counts(shared, installation), Some((1, 1)))
  }
  assert_true(
    settle_model_io_lease_holding_after_owner_ack(
      access, lease, ledger, reservation, 0, 1,
    )
    is Err(CleanupPending),
  )
  assert_true(!close_model_io_access(access).unwrap())
  assert_true(
    claim_model_io_access(access, foreign, foreign_reservation, 0, 1)
    is Err(AdmissionClosing),
  )
  settle_model_io_lease_after_owner_ack(
    access, lease, ledger, reservation, 0, 1,
  ).unwrap()
  assert_true(
    settle_model_io_lease_after_owner_ack(
      access, lease, ledger, reservation, 0, 1,
    )
    is Err(IoAlreadyRetired),
  )
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 1)))
  settle_model_io_lease_holding_after_owner_ack(
    access, lease, ledger, reservation, 0, 1,
  ).unwrap()
  assert_true(
    lease.access is None &&
    lease.settle_io is None &&
    lease.settle_holding is None,
  )
  assert_true(close_model_io_access(access).unwrap())
  assert_true(close_model_io_access(access).unwrap())
  assert_true(
    access.claim is None &&
    access.close is None &&
    access.leases is None &&
    access.within_limits is None &&
    access.can_claim is None,
  )
  assert_true(close_model_io_access(other).unwrap())
  assert_true(
    claim_model_io_access(access, ledger, reservation, 1, 1)
    is Err(AdmissionClosing),
  )
  assert_true(
    settle_model_io_lease_after_owner_ack(
      access, lease, ledger, reservation, 0, 1,
    )
    is Err(TicketRetired),
  )
}

///|
test "erased Model profile guard uses the same original limits and current installation" {
  let installation = Ref(0)
  let shared = issue_model_io_admission(installation, 2, 3).unwrap()
  let access = issue_model_io_access(shared, installation).unwrap()
  assert_true(model_io_access_within_limits(access, 2, 3))
  assert_true(model_io_access_within_limits(access, 4, 4))
  assert_false(model_io_access_within_limits(access, 1, 3))
  assert_false(model_io_access_within_limits(access, 2, 2))
  for (active, unsettled) in [(0, 3), (5, 3), (2, 0), (2, 5)] {
    assert_false(model_io_access_within_limits(access, active, unsettled))
  }
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 0)))
  shared.installation = Some(Ref(0))
  assert_false(model_io_access_within_limits(access, 4, 4))
  let (ledger, _, reservation) = model_io_test_run()
  assert_true(
    can_claim_model_io_access(access, ledger, reservation, 0, 1)
    is Err(ForeignInstallation),
  )
  shared.installation = Some(installation)
  assert_true(model_io_access_within_limits(access, 2, 3))
  assert_true(close_model_io_access(access).unwrap())
  assert_false(model_io_access_within_limits(access, 4, 4))
  assert_true(access.within_limits is None && access.can_claim is None)
}

///|
test "erased Model wait predicate is read-only and distinguishes exhaustion from typed failures" {
  let installation = Ref(0)
  let shared = issue_model_io_admission(installation, 1, 2).unwrap()
  let access = issue_model_io_access(shared, installation).unwrap()
  let (a, _, ra) = model_io_test_run()
  let (b, _, rb) = model_io_test_run()
  let (c, _, rc) = model_io_test_run()
  let before_a = ledger_usage(a)
  assert_eq(can_claim_model_io_access(access, a, ra, 0, 1), Ok(true))
  assert_eq(can_claim_model_io_access(access, a, ra, 0, 1), Ok(true))
  assert_eq(ledger_usage(a), before_a)
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 0)))
  let la = claim_model_io_access(access, a, ra, 0, 1).unwrap()
  let before_b = ledger_usage(b)
  assert_eq(can_claim_model_io_access(access, b, rb, 0, 1), Ok(false))
  assert_eq(ledger_usage(b), before_b)
  assert_true(
    can_claim_model_io_access(access, a, ra, 0, 1) is Err(DuplicateAttempt),
  )
  assert_true(
    can_claim_model_io_access(access, b, ra, 0, 1) is Err(ForeignTicket),
  )
  assert_true(
    can_claim_model_io_access(access, b, rb, -1, 1) is Err(InvalidAttempt),
  )
  settle_model_io_lease_after_owner_ack(access, la, a, ra, 0, 1).unwrap()
  assert_eq(can_claim_model_io_access(access, b, rb, 0, 1), Ok(true))
  let lb = claim_model_io_access(access, b, rb, 0, 1).unwrap()
  settle_model_io_lease_after_owner_ack(access, lb, b, rb, 0, 1).unwrap()
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 2)))
  let before_c = ledger_usage(c)
  assert_eq(can_claim_model_io_access(access, c, rc, 0, 1), Ok(false))
  assert_eq(ledger_usage(c), before_c)
  settle_model_io_lease_holding_after_owner_ack(access, la, a, ra, 0, 1).unwrap()
  assert_eq(can_claim_model_io_access(access, c, rc, 0, 1), Ok(true))
  assert_false(close_model_io_access(access).unwrap())
  assert_false(model_io_access_within_limits(access, 4, 4))
  assert_true(
    can_claim_model_io_access(access, c, rc, 0, 1) is Err(AdmissionClosing),
  )
  assert_true(access.within_limits is Some(_) && access.can_claim is Some(_))
  settle_model_io_lease_holding_after_owner_ack(access, lb, b, rb, 0, 1).unwrap()
  assert_true(close_model_io_access(access).unwrap())
  assert_true(
    can_claim_model_io_access(access, c, rc, 0, 1) is Err(AdmissionClosing),
  )
}

///|
test "erased Model wait readiness is not Ledger capacity or permission to claim" {
  let installation = Ref(0)
  let shared = issue_model_io_admission(installation, 1, 1).unwrap()
  let access = issue_model_io_access(shared, installation).unwrap()
  let (ledger, _, reservation) = model_io_test_run()
  let holdings = []
  for _ in 0..<4 {
    holdings.push(retain_allocation(ledger, reservation, 0L).unwrap())
  }
  let before = ledger_usage(ledger)
  assert_eq(
    can_claim_model_io_access(access, ledger, reservation, 0, 1),
    Ok(true),
  )
  assert_true(
    claim_model_io_access(access, ledger, reservation, 0, 1)
    is Err(Resource(HoldingLimit)),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 0)))
  for holding in holdings {
    release_allocation(ledger, holding).unwrap()
  }
  let ordinary = create_ledger(ledger_limits(ledger)).unwrap()
  assert_true(
    can_claim_model_io_access(access, ordinary, reservation, 0, 1)
    is Err(ForeignTicket),
  )
  assert_true(close_model_io_access(access).unwrap())
}

///|
test "erased Model access cannot retire another original ticket on failed cleanup" {
  let installation = Ref(0)
  let shared = issue_model_io_admission(installation, 2, 2).unwrap()
  let access = issue_model_io_access(shared, installation).unwrap()
  let (a, _, ra) = model_io_test_run()
  let (b, _, rb) = model_io_test_run()
  let la = claim_model_io_access(access, a, ra, 0, 1).unwrap()
  let lb = claim_model_io_access(access, b, rb, 0, 1).unwrap()
  let copied : ModelIoLease = { ..lb, }
  assert_true(
    settle_model_io_lease_after_owner_ack(access, copied, b, rb, 0, 1)
    is Err(ForeignTicket),
  )
  settle_model_io_lease_after_owner_ack(access, la, a, ra, 0, 1).unwrap()
  assert_true(
    settle_model_io_lease_holding_after_owner_ack(access, lb, a, ra, 0, 1)
    is Err(ForeignTicket),
  )
  assert_eq(model_io_admission_counts(shared, installation), Some((1, 2)))
  assert_true(
    lb.access is Some(_) &&
    lb.settle_io is Some(_) &&
    lb.settle_holding is Some(_),
  )
  settle_model_io_lease_holding_after_owner_ack(access, la, a, ra, 0, 1).unwrap()
  settle_model_io_lease_after_owner_ack(access, lb, b, rb, 0, 1).unwrap()
  settle_model_io_lease_holding_after_owner_ack(access, lb, b, rb, 0, 1).unwrap()
  assert_true(close_model_io_access(access).unwrap())
}

///|
test "four erased holdings forbid a fifth claim even after every I/O ACK" {
  let installation = Ref(0)
  let shared = issue_model_io_admission(installation, 4, 4).unwrap()
  let access = issue_model_io_access(shared, installation).unwrap()
  let duties : Array[(Ledger, Reservation, ModelIoLease)] = []
  for _ in 0..<4 {
    let (ledger, _, reservation) = model_io_test_run()
    let lease = claim_model_io_access(access, ledger, reservation, 0, 1).unwrap()
    settle_model_io_lease_after_owner_ack(
      access, lease, ledger, reservation, 0, 1,
    ).unwrap()
    duties.push((ledger, reservation, lease))
  }
  let (later, _, reservation) = model_io_test_run()
  let before = ledger_usage(later)
  assert_true(
    claim_model_io_access(access, later, reservation, 0, 1)
    is Err(HoldingExhausted),
  )
  assert_eq(ledger_usage(later), before)
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 4)))
  for (ledger, reservation, lease) in duties {
    settle_model_io_lease_holding_after_owner_ack(
      access, lease, ledger, reservation, 0, 1,
    ).unwrap()
  }
  assert_true(close_model_io_access(access).unwrap())
}
