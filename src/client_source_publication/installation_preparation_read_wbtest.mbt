///|
// Synthetic byte envelopes exercise the actual Resource/buffers protocol.
// They are not an installed Host layout, physical supplier or numeric profile.
fn installation_preparation_read_fixture(
  stopped : Ref[Bool],
  cleaned : Ref[Bool],
) -> (
  @resources.Ledger,
  Ref[Int],
  @resources.FundedReadClaim[Ref[Int]],
  @buffers.WorkspaceLoan,
  @buffers.OriginalWorkspaceRead[Ref[Int]],
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
  let loan = @buffers.reserve_workspace(ledger, 75L, () => stopped.val, () => {
    cleaned.val
  }).unwrap()
  let origin = Ref(0)
  let descriptor = @resources.issue_recorded_original_ledger_descriptor(
    identity, origin,
  ).unwrap()
  let claim = @resources.fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let pair = @buffers.issue_workspace_original_read(claim, origin, loan).unwrap()
  (ledger, origin, claim, loan, pair)
}

///|
test "installation preparation retains the original consumer after the read-pair borrow is consumed" {
  let (ledger, origin, claim, loan, pair) = installation_preparation_read_fixture(
    Ref(true),
    Ref(true),
  )
  let before = @resources.ledger_usage(ledger)
  let prepared = prepare_installation_preparation_read(
    pair, origin, loan, 7L, 5L,
  ).unwrap()
  assert_true(
    @buffers.borrow_workspace_original_read(pair, origin, loan) is None,
  )
  assert_true(installation_preparation_read_current(prepared, origin))
  assert_eq(@resources.ledger_usage(ledger), before)
  enter_installation_preparation_read(prepared, origin).unwrap()
  assert_true(installation_preparation_read_current(prepared, origin))
  assert_true(
    enter_installation_preparation_read(prepared, origin)
    is Err(@resources.SpentClaim),
  )
  assert_true(
    prepare_installation_preparation_read(pair, origin, loan, 7L, 5L) is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @buffers.close_workspace(loan).unwrap()
  @resources.settle_funded_read(claim, true).unwrap()
  retire_installation_preparation_read(prepared, origin).unwrap()
  assert_true(
    @resources.finish_funded_read_inventory(claim, origin, true).unwrap(),
  )
}

///|
test "installation preparation refuses foreign originals and loans before consuming either read" {
  let (ledger, origin, claim, loan, pair) = installation_preparation_read_fixture(
    Ref(true),
    Ref(true),
  )
  let (other_ledger, other_origin, other_claim, other_loan, _) = installation_preparation_read_fixture(
    Ref(true),
    Ref(true),
  )
  let before = @resources.ledger_usage(ledger)
  let other_before = @resources.ledger_usage(other_ledger)
  assert_true(
    prepare_installation_preparation_read(pair, other_origin, loan, 7L, 5L)
    is Err(_),
  )
  assert_true(
    prepare_installation_preparation_read(pair, origin, other_loan, 7L, 5L)
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.ledger_usage(other_ledger), other_before)
  assert_true(@resources.funded_read_available(claim, origin))
  assert_true(@resources.funded_read_available(other_claim, other_origin))
  let prepared = prepare_installation_preparation_read(
    pair, origin, loan, 7L, 5L,
  ).unwrap()
  assert_false(installation_preparation_read_current(prepared, other_origin))
  assert_true(
    enter_installation_preparation_read(prepared, other_origin)
    is Err(@resources.ForeignOrigin),
  )
  assert_true(
    retire_installation_preparation_read(prepared, other_origin)
    is Err(@resources.ForeignOrigin),
  )
  assert_true(installation_preparation_read_current(prepared, origin))
  @buffers.close_workspace(loan).unwrap()
  @buffers.close_workspace(other_loan).unwrap()
  @resources.settle_funded_read(claim, true).unwrap()
  @resources.settle_funded_read(other_claim, true).unwrap()
  retire_installation_preparation_read(prepared, origin).unwrap()
  assert_true(
    @resources.finish_funded_read_inventory(claim, origin, true).unwrap(),
  )
  assert_true(
    @resources.finish_funded_read_inventory(other_claim, other_origin, true).unwrap(),
  )
}

///|
test "installation preparation does not substitute a smaller or zero read envelope" {
  let (ledger, origin, claim, loan, pair) = installation_preparation_read_fixture(
    Ref(true),
    Ref(true),
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    prepare_installation_preparation_read(pair, origin, loan, 0L, 5L)
    is Err(@resources.Resource(@resources.InvalidCharge)),
  )
  assert_true(
    prepare_installation_preparation_read(pair, origin, loan, 7L, 0L)
    is Err(@resources.Resource(@resources.InvalidCharge)),
  )
  assert_true(
    prepare_installation_preparation_read(pair, origin, loan, 8L, 5L)
    is Err(@resources.Resource(@resources.RetentionLimit)),
  )
  assert_true(
    prepare_installation_preparation_read(pair, origin, loan, 7L, 6L)
    is Err(@resources.Resource(@resources.ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@resources.funded_read_available(claim, origin))
  let prepared = prepare_installation_preparation_read(
    pair, origin, loan, 7L, 5L,
  ).unwrap()
  @buffers.close_workspace(loan).unwrap()
  @resources.settle_funded_read(claim, true).unwrap()
  retire_installation_preparation_read(prepared, origin).unwrap()
  assert_true(
    @resources.finish_funded_read_inventory(claim, origin, true).unwrap(),
  )
}

///|
test "installation preparation does not turn pending workspace cleanup into read retirement" {
  let stopped = Ref(false)
  let cleaned = Ref(false)
  let (ledger, origin, claim, loan, pair) = installation_preparation_read_fixture(
    stopped, cleaned,
  )
  let prepared = prepare_installation_preparation_read(
    pair, origin, loan, 7L, 5L,
  ).unwrap()
  enter_installation_preparation_read(prepared, origin).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    retire_installation_preparation_read(prepared, origin)
    is Err(@resources.CleanupPending),
  )
  assert_eq(@buffers.close_workspace(loan), Err(@buffers.CleanupPending))
  assert_false(installation_preparation_read_current(prepared, origin))
  assert_true(
    enter_installation_preparation_read(prepared, origin)
    is Err(@resources.ChangedOriginalState),
  )
  assert_true(prepared.original is Some(_))
  assert_eq(@resources.ledger_usage(ledger), before)
  stopped.val = true
  assert_eq(@buffers.close_workspace(loan), Err(@buffers.CleanupPending))
  assert_true(prepared.original is Some(_))
  assert_true(
    retire_installation_preparation_read(prepared, origin)
    is Err(@resources.CleanupPending),
  )
  cleaned.val = true
  @buffers.close_workspace(loan).unwrap()
  assert_true(
    retire_installation_preparation_read(prepared, origin)
    is Err(@resources.CleanupPending),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 7L)
  @resources.settle_funded_read(claim, true).unwrap()
  retire_installation_preparation_read(prepared, origin).unwrap()
  assert_true(prepared.original is None)
  assert_false(installation_preparation_read_current(prepared, origin))
  assert_true(
    retire_installation_preparation_read(prepared, origin)
    is Err(@resources.SpentClaim),
  )
  assert_true(
    enter_installation_preparation_read(prepared, origin)
    is Err(@resources.SpentClaim),
  )
  assert_true(
    @resources.finish_funded_read_inventory(claim, origin, true).unwrap(),
  )
}

///|
test "installation preparation keeps stopped original read custody until independent workspace cleanup" {
  let (ledger, origin, claim, loan, pair) = installation_preparation_read_fixture(
    Ref(true),
    Ref(true),
  )
  let prepared = prepare_installation_preparation_read(
    pair, origin, loan, 7L, 5L,
  ).unwrap()
  @resources.stop_funded_read(claim).unwrap()
  assert_false(installation_preparation_read_current(prepared, origin))
  assert_true(
    @resources.settle_funded_read(claim, false)
    is Err(@resources.CleanupPending),
  )
  assert_true(
    retire_installation_preparation_read(prepared, origin)
    is Err(@resources.CleanupPending),
  )
  assert_true(prepared.original is Some(_))
  @resources.settle_funded_read(claim, true).unwrap()
  assert_true(
    retire_installation_preparation_read(prepared, origin)
    is Err(@resources.CleanupPending),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 77L)
  @buffers.close_workspace(loan).unwrap()
  retire_installation_preparation_read(prepared, origin).unwrap()
  assert_true(
    @resources.finish_funded_read_inventory(claim, origin, true).unwrap(),
  )
}
