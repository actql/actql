///|
fn original_workspace_pair_fixture(
  stopped : Ref[Bool],
  cleaned : Ref[Bool],
) -> (
  @resources.Ledger,
  Ref[Int],
  @resources.FundedReadClaim[Ref[Int]],
  WorkspaceLoan,
) {
  let ledger = @resources.create_ledger({
    planning_work: 10,
    attempts: 4,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 10L,
    execution_bytes: 82L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 4, 0, 0,
  ).unwrap()
  let loan = reserve_workspace(ledger, 75L, () => stopped.val, () => cleaned.val).unwrap()
  let origin = Ref(0)
  let descriptor = @resources.issue_recorded_original_ledger_descriptor(
    identity, origin,
  ).unwrap()
  let claim = @resources.fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  (ledger, origin, claim, loan)
}

///|
// A private typed preparation consumer captures this exact pair/loan before
// its phase transition. The amounts are abstract Ledger test charges, not
// physical prices or a numerical Host installation profile.
priv struct OriginalWorkspacePreparationFixture {
  pair : OriginalWorkspaceRead[Ref[Int]]
  loan : WorkspaceLoan
  origin : Ref[Int]
  consumer : @resources.FundedReadConsumer[Ref[Int]]
}

///|
fn original_workspace_preparation_fixture(
  pair : OriginalWorkspaceRead[Ref[Int]],
  origin : Ref[Int],
  loan : WorkspaceLoan,
) -> OriginalWorkspacePreparationFixture? {
  guard borrow_workspace_original_read(pair, origin, loan) is Some(claim) else {
    return None
  }
  let consumer = @resources.claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  Some({ pair, loan, origin, consumer, })
}

///|
fn original_workspace_preparation_current(
  value : OriginalWorkspacePreparationFixture,
) -> Bool {
  @resources.funded_read_consumer_available(
    value.consumer,
    value.origin,
    7L,
    5L,
  ) &&
  !value.loan.closing &&
  !value.loan.settled
}

///|
test "original preparation keeps its captured Loan current after leaving read phase" {
  let stopped = Ref(false)
  let cleaned = Ref(false)
  let (ledger, origin, claim, loan) = original_workspace_pair_fixture(
    stopped, cleaned,
  )
  let pair = issue_workspace_original_read(claim, origin, loan).unwrap()
  let before = @resources.ledger_usage(ledger)
  let preparation = original_workspace_preparation_fixture(pair, origin, loan).unwrap()
  assert_true(physical_equal(preparation.pair, pair))
  assert_true(physical_equal(preparation.loan, loan))
  assert_true(borrow_workspace_original_read(pair, origin, loan) is None)
  assert_true(original_workspace_preparation_current(preparation))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(close_workspace(loan), Err(CleanupPending))
  // The same reservation is still present. Consumer currentness alone cannot
  // observe a physical Loan's closing flag while its cleanup is pending.
  assert_true(
    @resources.funded_read_consumer_available(
      preparation.consumer,
      origin,
      7L,
      5L,
    ),
  )
  assert_true(!original_workspace_preparation_current(preparation))
  assert_true(!loan.stopped && !loan.cleaned && !loan.settled)
  assert_eq(@resources.ledger_usage(ledger), before)
  stopped.val = true
  assert_eq(close_workspace(loan), Err(CleanupPending))
  assert_true(!original_workspace_preparation_current(preparation))
  cleaned.val = true
  close_workspace(loan).unwrap()
  assert_true(!original_workspace_preparation_current(preparation))
  @resources.stop_funded_read_consumer(preparation.consumer).unwrap()
  @resources.settle_funded_read_consumer(preparation.consumer, true).unwrap()
  retire_workspace_original_read(pair, origin, loan).unwrap()
  assert_true(!original_workspace_preparation_current(preparation))
  assert_true(
    @resources.finish_funded_read_inventory(claim, origin, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "original preparation rejects replacement Loan before consuming its read" {
  let ledger = @resources.create_ledger({
    planning_work: 10,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 10L,
    execution_bytes: 57L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 4, 0, 0,
  ).unwrap()
  let first = reserve_workspace(ledger, 25L, () => true, () => true).unwrap()
  let second = reserve_workspace(ledger, 25L, () => true, () => true).unwrap()
  let origin = Ref(0)
  let descriptor = @resources.issue_recorded_original_ledger_descriptor(
    identity, origin,
  ).unwrap()
  let claim = @resources.fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let pair = issue_workspace_original_read(claim, origin, first).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    original_workspace_preparation_fixture(pair, origin, second) is None,
  )
  assert_true(
    original_workspace_preparation_fixture(pair, Ref(0), first) is None,
  )
  assert_true(workspace_original_read_matches(pair, claim, origin, first))
  assert_eq(@resources.ledger_usage(ledger), before)
  let preparation = original_workspace_preparation_fixture(pair, origin, first).unwrap()
  @resources.enter_funded_read_consumer(preparation.consumer, origin, 7L, 5L).unwrap()
  assert_true(original_workspace_preparation_current(preparation))
  close_workspace(first).unwrap()
  close_workspace(second).unwrap()
  @resources.stop_funded_read_consumer(preparation.consumer).unwrap()
  @resources.settle_funded_read_consumer(preparation.consumer, true).unwrap()
  retire_workspace_original_read(pair, origin, first).unwrap()
  assert_true(
    @resources.finish_funded_read_inventory(claim, origin, true).unwrap(),
  )
  assert_true(!original_workspace_preparation_current(preparation))
}

///|
test "original workspace pair retains read and physical Loan through independent cleanup acknowledgements" {
  let stopped = Ref(false)
  let cleaned = Ref(false)
  let (ledger, origin, claim, loan) = original_workspace_pair_fixture(
    stopped, cleaned,
  )
  let before = @resources.ledger_usage(ledger)
  let pair = issue_workspace_original_read(claim, origin, loan).unwrap()
  assert_true(workspace_original_read_matches(pair, claim, origin, loan))
  assert_true(
    physical_equal(
      borrow_workspace_original_read(pair, origin, loan).unwrap(),
      claim,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    retire_workspace_original_read(pair, origin, loan)
    is Err(@resources.CleanupPending),
  )
  assert_eq(close_workspace(loan), Err(CleanupPending))
  assert_true(borrow_workspace_original_read(pair, origin, loan) is None)
  assert_true(pair.binding is Some(_) && pair.loan is Some(_))
  assert_eq(@resources.ledger_usage(ledger), before)
  stopped.val = true
  assert_eq(close_workspace(loan), Err(CleanupPending))
  assert_true(!loan.cleaned && !loan.settled)
  assert_eq(@resources.ledger_usage(ledger), before)
  @resources.stop_funded_read(claim).unwrap()
  assert_true(
    @resources.settle_funded_read(claim, false)
    is Err(@resources.CleanupPending),
  )
  assert_true(
    retire_workspace_original_read(pair, origin, loan)
    is Err(@resources.CleanupPending),
  )
  cleaned.val = true
  close_workspace(loan).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 7L)
  assert_true(
    retire_workspace_original_read(pair, origin, loan)
    is Err(@resources.CleanupPending),
  )
  @resources.settle_funded_read(claim, true).unwrap()
  retire_workspace_original_read(pair, origin, loan).unwrap()
  assert_true(pair.binding is None && pair.loan is None)
  assert_true(borrow_workspace_original_read(pair, origin, loan) is None)
  assert_true(
    retire_workspace_original_read(pair, origin, loan)
    is Err(@resources.SpentClaim),
  )
  assert_true(
    @resources.finish_funded_read_inventory(claim, origin, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "original workspace pair refuses foreign Loan Origin and read without changing either original" {
  let (ledger, origin, claim, loan) = original_workspace_pair_fixture(
    Ref(true),
    Ref(true),
  )
  let (other_ledger, other_origin, other_claim, other_loan) = original_workspace_pair_fixture(
    Ref(true),
    Ref(true),
  )
  let before = @resources.ledger_usage(ledger)
  let other_before = @resources.ledger_usage(other_ledger)
  let pair = issue_workspace_original_read(claim, origin, loan).unwrap()
  assert_true(
    issue_workspace_original_read(claim, origin, other_loan)
    is Err(@resources.Resource(@resources.ForeignOwner)),
  )
  assert_true(
    issue_workspace_original_read(claim, other_origin, loan)
    is Err(@resources.ForeignOrigin),
  )
  assert_true(!workspace_original_read_matches(pair, other_claim, origin, loan))
  assert_true(!workspace_original_read_matches(pair, claim, origin, other_loan))
  assert_true(
    retire_workspace_original_read(pair, origin, other_loan)
    is Err(@resources.Resource(@resources.ForeignOwner)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.ledger_usage(other_ledger), other_before)
  close_workspace(loan).unwrap()
  close_workspace(other_loan).unwrap()
  @resources.settle_funded_read(claim, true).unwrap()
  @resources.settle_funded_read(other_claim, true).unwrap()
  assert_true(
    retire_workspace_original_read(pair, other_origin, loan)
    is Err(@resources.ForeignOrigin),
  )
  retire_workspace_original_read(pair, origin, loan).unwrap()
  assert_true(
    @resources.finish_funded_read_inventory(claim, origin, true).unwrap(),
  )
  assert_true(
    @resources.finish_funded_read_inventory(other_claim, other_origin, true).unwrap(),
  )
}

///|
test "original workspace pair rejects another recorded Loan on the same Ledger" {
  let ledger = @resources.create_ledger({
    planning_work: 10,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 10L,
    execution_bytes: 57L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 4, 0, 0,
  ).unwrap()
  let first = reserve_workspace(ledger, 25L, () => true, () => true).unwrap()
  let second = reserve_workspace(ledger, 25L, () => true, () => true).unwrap()
  let origin = Ref(0)
  let descriptor = @resources.issue_recorded_original_ledger_descriptor(
    identity, origin,
  ).unwrap()
  let claim = @resources.fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let pair = issue_workspace_original_read(claim, origin, first).unwrap()
  assert_true(workspace_original_read_matches(pair, claim, origin, first))
  assert_true(borrow_workspace_original_read(pair, origin, second) is None)
  assert_true(!workspace_original_read_matches(pair, claim, origin, second))
  assert_true(
    retire_workspace_original_read(pair, origin, second)
    is Err(@resources.Resource(@resources.ForeignOwner)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 57L)
  close_workspace(second).unwrap()
  assert_true(borrow_workspace_original_read(pair, origin, first) is None)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 32L)
  close_workspace(first).unwrap()
  @resources.settle_funded_read(claim, true).unwrap()
  retire_workspace_original_read(pair, origin, first).unwrap()
  assert_true(
    @resources.finish_funded_read_inventory(claim, origin, true).unwrap(),
  )
}
