///|
// Actual Core zero-byte reservations/delegations, with Ref physical originals.
// No Native mapping, worker, IO or physical stop acknowledgement is simulated.
fn backed_count_only_child_snapshot(kind : Int) -> (Ledger, LedgerUsage) raise {
  let child = create_ledger(backed_test_limits()).unwrap()
  match kind {
    0 => reserve_attempt(child, 0L, 0L, 0L).unwrap() |> ignore
    1 => reserve_capacity(child, 0L, 0L).unwrap() |> ignore
    2 =>
      reserve_execution_delegation(
        child,
        {
          planning_work: 0,
          attempts: 0,
          holdings: 0,
          transfer_bytes: 0L,
          retained_bytes: 0L,
          execution_bytes: 0L,
        },
        0L,
        0L,
      ).unwrap()
      |> ignore
    _ => abort("count-only fixture kind")
  }
  let usage = ledger_usage(child)
  assert_eq(usage.planning_work, 0)
  assert_eq(usage.attempts, 0)
  assert_eq(usage.holdings, 0)
  assert_eq(usage.transferred_bytes, 0L)
  assert_eq(usage.uncertain_transfer_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.peak_retention_bytes, 0L)
  assert_eq(usage.live_reservations, 1)
  (child, usage)
}

///|
test "count-only actual child report prevents first backed bootstrap" {
  for kind in 0..<3 {
    let (_, _, _, provider, region) = backed_test_region()
    let child = Ref(kind)
    let ticket = backed_read_test_ticket(region, provider, child)
    let read = borrow_backed_execution_read_use(region, provider, child, ticket).unwrap()
    let runtime = Ref(1)
    let access = issue_backed_execution_live_access(
      region, provider, child, ticket, read, runtime,
    ).unwrap()
    let (_, usage) = backed_count_only_child_snapshot(kind)
    report_backed_execution_delegation(region, provider, child, ticket, usage).unwrap()
    assert_true(
      admit_backed_execution_live_child(access, runtime)
      is Err(Resource(InvalidCharge)),
    )
  }
}

///|
test "count-only actual report history stays after unused zero-byte reservation settles" {
  let (_, _, projection, runtime) = backed_original_child_fixture()
  let frame = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  let child = create_ledger(backed_test_limits()).unwrap()
  let reservation = reserve_attempt(child, 0L, 0L, 0L).unwrap()
  report_backed_execution_live_child(projection, runtime, ledger_usage(child)).unwrap()
  settle_reservation(child, reservation).unwrap()
  assert_eq(ledger_usage(child).attempts, 0)
  assert_eq(ledger_usage(child).reserved_attempts, 0)
  assert_eq(ledger_usage(child).live_reservations, 0)
  report_backed_execution_live_child(projection, runtime, ledger_usage(child)).unwrap()
  assert_true(start_imported_child_ledger(frame) is Err(Unavailable))
  assert_true(frame.ledger is None)
}

///|
test "final usage identity distinguishes actual zero-byte child count snapshots" {
  let zero = ledger_usage(create_ledger(backed_test_limits()).unwrap())
  for kind in 0..<3 {
    let (_, usage) = backed_count_only_child_snapshot(kind)
    assert_false(backed_final_usage_equal(Some(zero), Some(usage)))
    assert_false(backed_final_usage_equal(Some(usage), Some(zero)))
  }
}

///|
test "held original shared return rejects changed final count snapshot after actual logical settlement" {
  let (parent, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = reserve_backed_execution_delegation(
    region,
    provider,
    child,
    backed_test_extent(),
    ReadOnly,
    backed_test_limits(),
    0L,
    0L,
  ).unwrap()
  let final_usage = ledger_usage(create_ledger(backed_test_limits()).unwrap())
  // Prepare the existing post-logical-settlement / pre-shared-return boundary.
  // This is a test-only phase cut, not a physical pending-return/ACK fault.
  settle_execution_delegation(
    parent,
    ticket.logical.unwrap(),
    Some(backed_logical_usage(final_usage)),
  ).unwrap()
  ticket.final_usage = Some(final_usage)
  assert_false(ticket.logical.unwrap().reservation.open)
  assert_eq(shared_allocation_usage(allocation).readers, 2)
  let before = ledger_usage(parent)
  let (_, changed) = backed_count_only_child_snapshot(0)
  assert_true(
    settle_backed_execution_after_owner_ack(
      region,
      provider,
      child,
      ticket,
      Some(changed),
    )
    is Err(ChangedFinalUsage),
  )
  assert_eq(shared_allocation_usage(allocation).readers, 2)
  assert_eq(ledger_usage(parent), before)
  settle_backed_execution_after_owner_ack(
    region,
    provider,
    child,
    ticket,
    Some(final_usage),
  ).unwrap()
  assert_eq(shared_allocation_usage(allocation).readers, 1)
  assert_true(close_backed_execution_region(region, provider).unwrap())
}
