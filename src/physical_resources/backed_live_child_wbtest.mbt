///|
// Portable parent accounting only. Ref originals and after-owner-ACK calls
// stand in for the physical issuer; no channel, VM, FD or worker is started.
fn backed_live_test_usage() -> LedgerUsage {
  {
    planning_work: 2,
    attempts: 1,
    holdings: 1,
    reserved_attempts: 0,
    live_reservations: 0,
    live_delegations: 0,
    transferred_bytes: 3L,
    uncertain_transfer_bytes: 1L,
    reserved_transfer_bytes: 0L,
    held_bytes: 2L,
    reserved_retention_bytes: 1L,
    reserved_execution_bytes: 4L,
    peak_retention_bytes: 3L,
  }
}

///|
test "backed live child keeps original allowance and cumulative reports without another reserve" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let runtime = Ref(3)
  let before = ledger_usage(ledger)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read_use, runtime,
  ).unwrap()
  let projection = admit_backed_execution_live_child(access, runtime).unwrap()
  assert_eq(
    backed_execution_live_limits(projection, runtime).unwrap(),
    backed_test_limits(),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 3)
  report_backed_execution_live_child(
    projection,
    runtime,
    backed_live_test_usage(),
  ).unwrap()
  let reported = ledger_usage(ledger)
  assert_eq(reported.planning_work, 2)
  assert_eq(reported.attempts, before.attempts + 2)
  assert_eq(reported.transferred_bytes, 3L)
  assert_eq(reported.uncertain_transfer_bytes, 1L)
  assert_eq(reported.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(reported.reserved_retention_bytes, before.reserved_retention_bytes)
  report_backed_execution_live_child(
    projection,
    runtime,
    backed_live_test_usage(),
  ).unwrap()
  assert_eq(ledger_usage(ledger), reported)
}

///|
test "backed live child access and admission are one shot including lost reply" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let runtime = Ref(3)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read_use, runtime,
  ).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    issue_backed_execution_live_access(
      region, provider, child, ticket, read_use, runtime,
    )
    is Err(LiveAccessAlreadyIssued),
  )
  // The caller loses the admission reply, but the original Owner keeps it.
  let _ = admit_backed_execution_live_child(access, runtime).unwrap()
  assert_true(
    admit_backed_execution_live_child(access, runtime)
    is Err(LiveChildAlreadyAdmitted),
  )
  assert_true(access.projection is Some(_))
  assert_true(read_use.live_access_pending)
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 3)
}

///|
test "backed live child rejects copied access projection and same valued runtime" {
  let (ledger, _, _, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let runtime = Ref(3)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read_use, runtime,
  ).unwrap()
  let copied_access = { ..access, }
  assert_true(
    admit_backed_execution_live_child(copied_access, runtime)
    is Err(ForeignOriginal),
  )
  assert_true(
    admit_backed_execution_live_child(access, Ref(3)) is Err(ForeignOriginal),
  )
  let projection = admit_backed_execution_live_child(access, runtime).unwrap()
  let copied_projection = { ..projection, }
  let before = ledger_usage(ledger)
  assert_true(
    report_backed_execution_live_child(
      copied_projection,
      runtime,
      backed_live_test_usage(),
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    report_backed_execution_live_child(
      projection,
      Ref(3),
      backed_live_test_usage(),
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    retire_backed_execution_live_child_after_owner_ack(access, Ref(3))
    is Err(ForeignOriginal),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(read_use.live_access_pending)
}

///|
test "backed live child validates original parent child and read use before issuing" {
  let (ledger, _, _, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let runtime = Ref(3)
  let before = ledger_usage(ledger)
  assert_true(
    issue_backed_execution_live_access(
      region,
      Ref(1),
      child,
      ticket,
      read_use,
      runtime,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    issue_backed_execution_live_access(
      region,
      provider,
      Ref(2),
      ticket,
      read_use,
      runtime,
    )
    is Err(ForeignOriginal),
  )
  let (_, _, _, other_provider, other_region) = backed_test_region()
  let other_child = Ref(2)
  let other_ticket = backed_read_test_ticket(
    other_region, other_provider, other_child,
  )
  assert_true(
    issue_backed_execution_live_access(
      other_region, other_provider, other_child, other_ticket, read_use, runtime,
    )
    is Err(ForeignOriginal),
  )
  assert_false(read_use.live_access_issued)
  assert_false(read_use.live_access_pending)
  assert_eq(ledger_usage(ledger), before)
}

///|
test "backed live child closing preserves reports and rejects new work without refund" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let runtime = Ref(3)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read_use, runtime,
  ).unwrap()
  let projection = admit_backed_execution_live_child(access, runtime).unwrap()
  let before_state = ledger_usage(ledger)
  assert_eq(backed_execution_live_state(projection, runtime).unwrap(), LiveOpen)
  assert_true(
    backed_execution_live_state(projection, Ref(3)) is Err(ForeignOriginal),
  )
  assert_eq(ledger_usage(ledger), before_state)
  stop_backed_execution_live_child(access, runtime).unwrap()
  stop_backed_execution_live_child(access, runtime).unwrap()
  assert_eq(
    backed_execution_live_state(projection, runtime).unwrap(),
    LiveClosing,
  )
  assert_true(
    backed_execution_live_limits(projection, runtime) is Err(RegionClosing),
  )
  report_backed_execution_live_child(
    projection,
    runtime,
    backed_live_test_usage(),
  ).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    report_backed_execution_live_child(projection, runtime, {
      ..backed_live_test_usage(),
      planning_work: 1,
    })
    is Err(Resource(InvalidCharge)),
  )
  assert_true(
    report_backed_execution_live_child(projection, runtime, {
      ..backed_live_test_usage(),
      reserved_execution_bytes: 21L,
    })
    is Err(Resource(InvalidCharge)),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 3)
}

///|
test "backed live child retirement separates reference read and confirmed stop acknowledgements" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let runtime = Ref(3)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read_use, runtime,
  ).unwrap()
  let projection = admit_backed_execution_live_child(access, runtime).unwrap()
  report_backed_execution_live_child(
    projection,
    runtime,
    backed_live_test_usage(),
  ).unwrap()
  stop_backed_execution_read_use(region, provider, child, ticket, read_use).unwrap()
  let before = ledger_usage(ledger)
  // Neither a cancel/EOF nor a report is the outstanding runtime retirement.
  assert_true(
    return_backed_execution_read_use_after_owner_ack(
      region, provider, child, ticket, read_use,
    )
    is Err(CleanupPending),
  )
  assert_true(
    settle_backed_execution_after_owner_ack(
      region,
      provider,
      child,
      ticket,
      None,
    )
    is Err(CleanupPending),
  )
  retire_backed_execution_live_child_after_owner_ack(access, runtime).unwrap()
  assert_true(projection.access is None && access.original is None)
  assert_true(
    access.runtime is None && access.region is None && access.ticket is None,
  )
  assert_true(
    access.provider is None &&
    access.child is None &&
    access.read_use is None &&
    access.projection is None,
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 3)
  assert_true(backed_execution_live_limits(projection, runtime) is Err(Retired))
  assert_true(
    admit_backed_execution_live_child(access, runtime) is Err(Retired),
  )
  assert_true(
    retire_backed_execution_live_child_after_owner_ack(access, runtime)
    is Err(Retired),
  )
  assert_true(
    issue_backed_execution_live_access(
      region, provider, child, ticket, read_use, runtime,
    )
    is Err(RegionClosing),
  )
  return_backed_execution_read_use_after_owner_ack(
    region, provider, child, ticket, read_use,
  ).unwrap()
  assert_eq(shared_allocation_usage(allocation).readers, 2)
  assert_eq(ledger_usage(ledger), before)
  settle_backed_execution_after_owner_ack(region, provider, child, ticket, None).unwrap()
  assert_eq(shared_allocation_usage(allocation).readers, 1)
  assert_eq(ledger_usage(ledger).planning_work, 4)
  // Pure arena capacity consumes no attempt; provisioning1 + unknown quota2.
  assert_eq(ledger_usage(ledger).attempts, 3)
  assert_eq(ledger_usage(ledger).transferred_bytes, 3L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 7L)
}

///|
test "backed live child refuses closing and previously used tickets instead of resetting usage" {
  let (ledger, _, _, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let runtime = Ref(3)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read_use, runtime,
  ).unwrap()
  report_backed_execution_delegation(
    region,
    provider,
    child,
    ticket,
    backed_live_test_usage(),
  ).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    admit_backed_execution_live_child(access, runtime)
    is Err(Resource(InvalidCharge)),
  )
  assert_true(access.projection is None && read_use.live_access_pending)
  assert_eq(ledger_usage(ledger), before)
  assert_false(close_backed_execution_region(region, provider).unwrap())
  assert_true(
    admit_backed_execution_live_child(access, runtime) is Err(RegionClosing),
  )
  // Closing still permits same-original retirement, not automatic settlement.
  retire_backed_execution_live_child_after_owner_ack(access, runtime).unwrap()
  return_backed_execution_read_use_after_owner_ack(
    region, provider, child, ticket, read_use,
  ).unwrap()
  settle_backed_execution_after_owner_ack(region, provider, child, ticket, None).unwrap()
}

///|
fn backed_live_test_zero_usage() -> LedgerUsage {
  {
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    reserved_attempts: 0,
    live_reservations: 0,
    live_delegations: 0,
    transferred_bytes: 0L,
    uncertain_transfer_bytes: 0L,
    reserved_transfer_bytes: 0L,
    held_bytes: 0L,
    reserved_retention_bytes: 0L,
    reserved_execution_bytes: 0L,
    peak_retention_bytes: 0L,
  }
}

///|
test "backed live child refuses reservation-only transfer history even after zero" {
  // A failed nonzero report and a successful zero-only check must not
  // consume first admission. This independent ticket is the positive control.
  let (_, _, _, clean_provider, clean_region) = backed_test_region()
  let clean_child = Ref(20)
  let clean_ticket = backed_read_test_ticket(
    clean_region, clean_provider, clean_child,
  )
  let clean_use = borrow_backed_execution_read_use(
    clean_region, clean_provider, clean_child, clean_ticket,
  ).unwrap()
  let clean_runtime = Ref(30)
  let clean_access = issue_backed_execution_live_access(
    clean_region, clean_provider, clean_child, clean_ticket, clean_use, clean_runtime,
  ).unwrap()
  assert_true(
    report_backed_execution_delegation(
      clean_region,
      clean_provider,
      clean_child,
      clean_ticket,
      {
        ..backed_live_test_zero_usage(),
        reserved_transfer_bytes: backed_test_limits().transfer_bytes + 1L,
      },
    )
    is Err(Resource(InvalidCharge)),
  )
  report_backed_execution_delegation(
    clean_region,
    clean_provider,
    clean_child,
    clean_ticket,
    backed_live_test_zero_usage(),
  ).unwrap()
  assert_true(
    admit_backed_execution_live_child(clean_access, clean_runtime) is Ok(_),
  )
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let runtime = Ref(3)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read_use, runtime,
  ).unwrap()
  // Every other usage field, including retention peak, is independently zero.
  report_backed_execution_delegation(region, provider, child, ticket, {
    ..backed_live_test_zero_usage(),
    reserved_transfer_bytes: 1L,
  }).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    admit_backed_execution_live_child(access, runtime)
    is Err(Resource(InvalidCharge)),
  )
  report_backed_execution_delegation(
    region,
    provider,
    child,
    ticket,
    backed_live_test_zero_usage(),
  ).unwrap()
  assert_true(
    admit_backed_execution_live_child(access, runtime)
    is Err(Resource(InvalidCharge)),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 3)
}

///|
test "backed live child refuses reservation-only execution history even after zero" {
  // A failed nonzero report and a successful zero-only check must not
  // consume first admission. This independent ticket is the positive control.
  let (_, _, _, clean_provider, clean_region) = backed_test_region()
  let clean_child = Ref(20)
  let clean_ticket = backed_read_test_ticket(
    clean_region, clean_provider, clean_child,
  )
  let clean_use = borrow_backed_execution_read_use(
    clean_region, clean_provider, clean_child, clean_ticket,
  ).unwrap()
  let clean_runtime = Ref(30)
  let clean_access = issue_backed_execution_live_access(
    clean_region, clean_provider, clean_child, clean_ticket, clean_use, clean_runtime,
  ).unwrap()
  assert_true(
    report_backed_execution_delegation(
      clean_region,
      clean_provider,
      clean_child,
      clean_ticket,
      {
        ..backed_live_test_zero_usage(),
        reserved_execution_bytes: backed_test_limits().execution_bytes + 1L,
      },
    )
    is Err(Resource(InvalidCharge)),
  )
  report_backed_execution_delegation(
    clean_region,
    clean_provider,
    clean_child,
    clean_ticket,
    backed_live_test_zero_usage(),
  ).unwrap()
  assert_true(
    admit_backed_execution_live_child(clean_access, clean_runtime) is Ok(_),
  )
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let runtime = Ref(3)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read_use, runtime,
  ).unwrap()
  // Every other usage field, including retention peak, is independently zero.
  report_backed_execution_delegation(region, provider, child, ticket, {
    ..backed_live_test_zero_usage(),
    reserved_execution_bytes: 1L,
  }).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    admit_backed_execution_live_child(access, runtime)
    is Err(Resource(InvalidCharge)),
  )
  report_backed_execution_delegation(
    region,
    provider,
    child,
    ticket,
    backed_live_test_zero_usage(),
  ).unwrap()
  assert_true(
    admit_backed_execution_live_child(access, runtime)
    is Err(Resource(InvalidCharge)),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 3)
}
