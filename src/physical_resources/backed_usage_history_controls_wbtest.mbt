///|
test "backed usage equality distinguishes each formerly missing live count independently" {
  let zero = ledger_usage(create_ledger(backed_test_limits()).unwrap())
  let (_, attempted) = backed_count_only_child_snapshot(0)
  let (_, capacity) = backed_count_only_child_snapshot(1)
  let (_, delegated) = backed_count_only_child_snapshot(2)
  // Every pair differs in exactly the named counter, all other twelve fields
  // come from actual same-limit Core Ledgers and independently agree.
  assert_eq({ ..attempted, reserved_attempts: 0, }, capacity)
  assert_eq({ ..capacity, live_reservations: 0, }, zero)
  assert_eq({ ..delegated, live_delegations: 0, }, attempted)
  for
    (left, right) in [
      (attempted, capacity),
      (capacity, zero),
      (delegated, attempted),
    ] {
    assert_false(backed_final_usage_equal(Some(left), Some(right)))
    assert_false(backed_final_usage_equal(Some(right), Some(left)))
  }
  assert_true(backed_final_usage_equal(Some(zero), Some({ ..zero, })))
  assert_true(backed_final_usage_equal(None, None))
  assert_false(backed_final_usage_equal(None, Some(zero)))
  assert_false(backed_final_usage_equal(Some(zero), None))
}

///|
test "backed failed count report leaves unused admission available" {
  let (_, _, _, provider, region) = backed_test_region()
  let child = Ref(1)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read = borrow_backed_execution_read_use(region, provider, child, ticket).unwrap()
  let runtime = Ref(2)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read, runtime,
  ).unwrap()
  let zero = ledger_usage(create_ledger(backed_test_limits()).unwrap())
  let before = ledger_usage(region.capacity.unwrap().ledger)
  assert_true(
    report_backed_execution_delegation(region, provider, child, ticket, {
      ..zero,
      reserved_attempts: backed_test_limits().attempts + 1,
    })
    is Err(Resource(InvalidCharge)),
  )
  assert_false(ticket.live_usage_reported)
  assert_eq(ledger_usage(region.capacity.unwrap().ledger), before)
  report_backed_execution_delegation(region, provider, child, ticket, zero).unwrap()
  assert_true(admit_backed_execution_live_child(access, runtime) is Ok(_))
}

///|
test "backed first-use gates inspect original logical live counts even without report marker" {
  for kind in 0..<3 {
    let (parent, _, projection, runtime) = backed_original_child_fixture()
    let access = projection.access.unwrap()
    let ticket = access.ticket.unwrap()
    // A direct same-Owner logical accounting boundary still must not bypass
    // either gate. This is no external callback/factory or physical child.
    let (_, usage) = backed_count_only_child_snapshot(kind)
    report_execution_delegation(
      parent,
      ticket.logical.unwrap(),
      backed_logical_usage(usage),
    ).unwrap()
    assert_false(ticket.live_usage_reported)
    assert_false(backed_original_child_ready(projection, runtime))
    assert_true(
      prepare_backed_original_child_ledger(projection, runtime)
      is Err(Unavailable),
    )
  }
}
