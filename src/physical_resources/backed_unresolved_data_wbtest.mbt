///|
// Independent portable accounting vectors. Owner ACK calls below are doubles;
// no native worker/FD/Store/current epoch or cold restore is exercised here.
fn backed_data_fixture() -> (
  Ledger,
  Ref[Int],
  Ref[Int],
  BackedExecutionRegion[Ref[Int], Ref[Int]],
  BackedExecutionDelegation[Ref[Int], Ref[Int]],
) {
  let (ledger, _, _, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = reserve_backed_execution_delegation(
    region,
    provider,
    child,
    backed_test_extent(),
    ExclusiveWrite,
    backed_test_limits(),
    5L,
    7L,
  ).unwrap()
  (ledger, provider, child, region, ticket)
}

///|
test "backed unresolved DATA projects same live quota overhead and unobserved final usage" {
  let (ledger, provider, child, region, ticket) = backed_data_fixture()
  let before = ledger_usage(ledger)
  let data = issue_backed_execution_original_data(
    region, provider, child, ticket,
  ).unwrap()
  assert_eq(data.allocation_bytes, 80L)
  assert_eq(data.extent, backed_test_extent())
  assert_eq(data.access, ExclusiveWrite)
  assert_eq(data.limits, backed_test_limits())
  assert_eq(data.cumulative, {
    planning_work: 0,
    attempts: 0,
    transferred_bytes: 0L,
    uncertain_transfer_bytes: 0L,
  })
  assert_eq(data.provision, {
    transfer_bytes: 10L,
    retained_bytes: 5L,
    execution_bytes: 7L,
    open: true,
    cleanup_pending: false,
  })
  assert_eq(data.read_use, NotIssued)
  assert_true(data.final_usage is None)
  let observation = admit_unresolved_backed_execution_data(data).unwrap()
  assert_eq(unresolved_backed_execution_data(observation), data)
  assert_eq(
    ledger_usage(ledger),
    before,
    msg="projection/admission cannot reserve or return credit",
  )
}

///|
test "backed unresolved DATA keeps cumulative debt and immutable earlier snapshot" {
  let (ledger, provider, child, region, ticket) = backed_data_fixture()
  let first = issue_backed_execution_original_data(
    region, provider, child, ticket,
  ).unwrap()
  let usage = {
    ..ledger_usage(create_ledger(backed_test_limits()).unwrap()),
    planning_work: 2,
    attempts: 1,
    holdings: 2,
    reserved_attempts: 0,
    live_reservations: 0,
    live_delegations: 0,
    transferred_bytes: 4L,
    uncertain_transfer_bytes: 1L,
    held_bytes: 10L,
    reserved_retention_bytes: 2L,
    reserved_execution_bytes: 20L,
    peak_retention_bytes: 12L,
  }
  report_backed_execution_delegation(region, provider, child, ticket, usage).unwrap()
  let before = ledger_usage(ledger)
  let next = issue_backed_execution_original_data(
    region, provider, child, ticket,
  ).unwrap()
  assert_eq(next.cumulative, {
    planning_work: 2,
    attempts: 1,
    transferred_bytes: 4L,
    uncertain_transfer_bytes: 1L,
  })
  assert_eq(next.occupation, {
    holdings: 2,
    reserved_attempts: 0,
    live_reservations: 0,
    live_delegations: 0,
  })
  assert_eq(next.provision.transfer_bytes, 5L)
  assert_eq(next.peak_retention_bytes, 12L)
  assert_true(next.final_usage is None)
  admit_unresolved_backed_execution_data(next).unwrap() |> ignore
  assert_eq(first.cumulative.transferred_bytes, 0L)
  assert_eq(first.provision.transfer_bytes, 10L)
  assert_eq(ledger_usage(ledger), before)
}

///|
test "backed unresolved DATA refuses foreign region provider child and copied ticket" {
  let (ledger, provider, child, region, ticket) = backed_data_fixture()
  let (_, _, _, _, other) = backed_test_region()
  let copied : BackedExecutionDelegation[Ref[Int], Ref[Int]] = { ..ticket, }
  let before = ledger_usage(ledger)
  for
    (selected, actual_provider, actual_child, actual_ticket) in [
      (other, provider, child, ticket),
      (region, Ref(1), child, ticket),
      (region, provider, Ref(2), ticket),
      (region, provider, child, copied),
    ] {
    assert_true(
      issue_backed_execution_original_data(
        selected, actual_provider, actual_child, actual_ticket,
      )
      is Err(ForeignOriginal),
    )
  }
  assert_eq(ledger_usage(ledger), before)
}

///|
test "backed unresolved DATA retains issued pending closing and retired read use" {
  let (ledger, provider, child, region, ticket) = backed_data_fixture()
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let before = ledger_usage(ledger)
  assert_eq(
    issue_backed_execution_original_data(region, provider, child, ticket).unwrap().read_use,
    Pending,
  )
  stop_backed_execution_read_use(region, provider, child, ticket, read_use).unwrap()
  let closing = issue_backed_execution_original_data(
    region, provider, child, ticket,
  ).unwrap()
  assert_eq(closing.read_use, Closing)
  assert_true(closing.provision.open)
  assert_true(closing.final_usage is None)
  admit_unresolved_backed_execution_data(closing).unwrap() |> ignore
  return_backed_execution_read_use_after_owner_ack(
    region, provider, child, ticket, read_use,
  ).unwrap()
  assert_eq(
    issue_backed_execution_original_data(region, provider, child, ticket).unwrap().read_use,
    Retired,
  )
  assert_eq(ledger_usage(ledger), before)
}

///|
test "backed unresolved DATA rejects negative overflow inconsistent and fabricated final facts" {
  let (ledger, provider, child, region, ticket) = backed_data_fixture()
  let data = issue_backed_execution_original_data(
    region, provider, child, ticket,
  ).unwrap()
  let max = 9223372036854775807L
  let before = ledger_usage(ledger)
  for
    invalid in [
      { ..data, allocation_bytes: -1L, },
      {
        ..data,
        extent: { ..data.extent, offset: max, length: 1L, },
        allocation_bytes: max,
      },
      { ..data, limits: { ..data.limits, retained_bytes: 33L, }, },
      { ..data, cumulative: { ..data.cumulative, transferred_bytes: 11L, }, },
      {
        ..data,
        cumulative: { ..data.cumulative, uncertain_transfer_bytes: -1L, },
      },
      { ..data, provision: { ..data.provision, transfer_bytes: 9L, }, },
      {
        ..data,
        final_usage: Some(ledger_usage(create_ledger(data.limits).unwrap())),
      },
      { ..data, provision: { ..data.provision, open: false, }, },
    ] {
    assert_true(
      admit_unresolved_backed_execution_data(invalid) is Err(InvalidData),
    )
  }
  assert_eq(ledger_usage(ledger), before)
}

///|
test "backed unresolved closed unknown DATA consumes original debt without a cold authority" {
  let (_, provider, child, region, ticket) = backed_data_fixture()
  let issued = issue_backed_execution_original_data(
    region, provider, child, ticket,
  ).unwrap()
  // Independent cold DATA vector, not a live ticket or confirmed stop.
  let data = {
    ..issued,
    cumulative: {
      planning_work: 4,
      attempts: 2,
      transferred_bytes: 4L,
      uncertain_transfer_bytes: 6L,
    },
    provision: {
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 0L,
      open: false,
      cleanup_pending: false,
    },
    read_use: Retired,
    final_usage: None,
  }
  let observation = admit_unresolved_backed_execution_data(data).unwrap()
  assert_eq(unresolved_backed_execution_data(observation), data)
  assert_true(unresolved_backed_execution_data(observation).final_usage is None)
  assert_true(
    admit_unresolved_backed_execution_data({
      ..data,
      cumulative: { ..data.cumulative, uncertain_transfer_bytes: 0L, },
    })
    is Err(InvalidData),
  )
  // The real original ticket is unaffected; observation contains no issuer.
  assert_eq(
    issue_backed_execution_original_data(region, provider, child, ticket).unwrap(),
    issued,
  )
}

///|
test "backed unresolved DATA cannot project a retired original ticket" {
  let (_, provider, child, region, ticket) = backed_data_fixture()
  let data = issue_backed_execution_original_data(
    region, provider, child, ticket,
  ).unwrap()
  settle_backed_execution_after_owner_ack(region, provider, child, ticket, None).unwrap()
  assert_true(
    issue_backed_execution_original_data(region, provider, child, ticket)
    is Err(_),
  )
  assert_true(admit_unresolved_backed_execution_data(data) is Ok(_))
  // Reading a saved earlier DATA value cannot undo ticket retirement.
  assert_true(
    issue_backed_execution_original_data(region, provider, child, ticket)
    is Err(_),
  )
}

///|
test "backed unresolved known final DATA retains its exact nonzero observations" {
  let (_, provider, child, region, ticket) = backed_data_fixture()
  let issued = issue_backed_execution_original_data(
    region, provider, child, ticket,
  ).unwrap()
  let usage = {
    planning_work: 3,
    attempts: 1,
    holdings: 2,
    reserved_attempts: 0,
    live_reservations: 0,
    live_delegations: 0,
    transferred_bytes: 4L,
    uncertain_transfer_bytes: 1L,
    reserved_transfer_bytes: 0L,
    held_bytes: 0L,
    reserved_retention_bytes: 0L,
    reserved_execution_bytes: 0L,
    peak_retention_bytes: 12L,
  }
  let data = {
    ..issued,
    cumulative: {
      planning_work: 3,
      attempts: 1,
      transferred_bytes: 4L,
      uncertain_transfer_bytes: 1L,
    },
    peak_retention_bytes: 10L,
    provision: {
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 0L,
      open: false,
      cleanup_pending: false,
    },
    final_usage: Some(usage),
  }
  let observation = admit_unresolved_backed_execution_data(data).unwrap()
  assert_eq(
    unresolved_backed_execution_data(observation).final_usage,
    Some(usage),
  )
  assert_true(
    admit_unresolved_backed_execution_data({
      ..data,
      final_usage: Some({ ..usage, transferred_bytes: 3L, }),
    })
    is Err(InvalidData),
  )
  assert_eq(
    issue_backed_execution_original_data(region, provider, child, ticket).unwrap(),
    issued,
  )
}
