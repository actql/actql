///|
fn original_workspace_binding_fixture() -> (
  Ledger,
  Ref[Int],
  FundedReadClaim[Ref[Int]],
  SharedCapacity,
) {
  let ledger = create_ledger({
    planning_work: 10,
    attempts: 4,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 10L,
    execution_bytes: 82L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let capacity = reserve_shared_capacity(ledger, 75L).unwrap()
  let origin = Ref(0)
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  (ledger, origin, claim, capacity)
}

///|
test "original workspace binding borrows the exact recorded claim without additional reservation" {
  let (ledger, origin, claim, capacity) = original_workspace_binding_fixture()
  let before = ledger_usage(ledger)
  let binding = issue_original_read_workspace_binding(claim, origin, capacity).unwrap()
  assert_eq(ledger_usage(ledger), before)
  assert_true(
    original_read_workspace_binding_current(binding, origin, capacity),
  )
  assert_true(
    physical_equal(
      borrow_original_read_workspace_claim(binding, origin, capacity).unwrap(),
      claim,
    ),
  )
  let (_, other_origin, other_claim, other_capacity) = original_workspace_binding_fixture()
  assert_true(
    issue_original_read_workspace_binding(claim, other_origin, capacity)
    is Err(ForeignOrigin),
  )
  assert_true(
    issue_original_read_workspace_binding(other_claim, other_origin, capacity)
    is Err(Resource(ForeignOwner)),
  )
  assert_true(
    borrow_original_read_workspace_claim(binding, origin, other_capacity)
    is None,
  )
  assert_true(
    borrow_original_read_workspace_claim(binding, other_origin, capacity)
    is None,
  )
  settle_funded_read(other_claim, true).unwrap()
  close_shared_capacity(other_capacity).unwrap()
  settle_shared_capacity(other_capacity).unwrap()
  finish_funded_read_inventory(other_claim, other_origin, true).unwrap()
  |> ignore
  assert_true(
    retire_original_read_workspace_binding(binding, origin, capacity)
    is Err(CleanupPending),
  )
  stop_funded_read(claim).unwrap()
  assert_true(
    borrow_original_read_workspace_claim(binding, origin, capacity) is None,
  )
  assert_true(settle_funded_read(claim, false) is Err(CleanupPending))
  assert_eq(ledger_usage(ledger), before)
  settle_funded_read(claim, true).unwrap()
  assert_true(
    retire_original_read_workspace_binding(binding, origin, capacity)
    is Err(CleanupPending),
  )
  close_shared_capacity(capacity).unwrap()
  settle_shared_capacity(capacity).unwrap()
  retire_original_read_workspace_binding(binding, origin, capacity).unwrap()
  assert_true(binding.claim is None && binding.capacity is None)
  assert_true(
    retire_original_read_workspace_binding(binding, origin, capacity)
    is Err(SpentClaim),
  )
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
}

///|
test "original workspace binding refuses unrecorded and changed reservation state" {
  let (ledger, origin, claim, capacity) = original_workspace_binding_fixture()
  // Negative fixture: a capacity shell around bootstrap is not the recorded
  // workspace. No physical provider/Loan is manufactured by this test input.
  let bootstrap = claim.descriptor.bootstrap
  let shell : SharedCapacity = {
    ledger,
    reservation: bootstrap.reservation,
    capacity: 2L,
    allocated: 0L,
    closing: false,
    growth: None,
  }
  assert_true(
    issue_original_read_workspace_binding(claim, origin, shell)
    is Err(IncompleteInventory),
  )
  let binding = issue_original_read_workspace_binding(claim, origin, capacity).unwrap()
  mark_cleanup_pending(ledger, capacity.reservation).unwrap()
  assert_true(
    !original_read_workspace_binding_current(binding, origin, capacity),
  )
  assert_true(
    issue_original_read_workspace_binding(claim, origin, capacity)
    is Err(ChangedOriginalState),
  )
  settle_funded_read(claim, true).unwrap()
  close_shared_capacity(capacity).unwrap()
  settle_shared_capacity(capacity).unwrap()
  retire_original_read_workspace_binding(binding, origin, capacity).unwrap()
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
}
