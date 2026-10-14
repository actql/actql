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
    access.claim is None && access.close is None && access.leases is None,
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
