///|
// Count/identity/census vectors only. Retirement calls stand in for the
// existing Model Owner's verified ACK, not actual physical/Store evidence.
fn model_io_test_run() -> (Ledger, OriginalLedgerIdentity, Reservation) {
  let ledger = create_ledger({
    planning_work: 16,
    attempts: 4,
    holdings: 4,
    transfer_bytes: 100L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 10L, 10L).unwrap()
  let origin = begin_original_ledger_inventory(ledger, bootstrap, 4, 4, 0).unwrap()
  let attempt = reserve_attempt(ledger, 1L, 10L, 10L).unwrap()
  (ledger, origin, attempt)
}

///|
test "Model shared availability uses the declared initial slot domain only" {
  let installation = Ref(0)
  assert_true(issue_model_io_admission(installation, 0, 1) is Err(InvalidLimits))
  assert_true(issue_model_io_admission(installation, 1, 0) is Err(InvalidLimits))
  assert_true(issue_model_io_admission(installation, 5, 4) is Err(InvalidLimits))
  assert_true(issue_model_io_admission(installation, 4, 5) is Err(InvalidLimits))
  let shared = issue_model_io_admission(installation, 4, 4).unwrap()
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 0)))
  assert_true(close_model_io_admission(shared, installation).unwrap())
  assert_eq(model_io_admission_counts(shared, installation), None)
}

///|
test "two original Runs share I/O and keep independent unsettled Store custody" {
  let installation = Ref(0)
  let shared = issue_model_io_admission(installation, 1, 2).unwrap()
  let (ledger_a, origin_a, attempt_a) = model_io_test_run()
  let (ledger_b, origin_b, attempt_b) = model_io_test_run()
  let a = claim_model_io_admission(shared, installation, origin_a, attempt_a, 0, 1).unwrap()
  let b_before = ledger_usage(ledger_b)
  assert_true(
    claim_model_io_admission(shared, installation, origin_b, attempt_b, 0, 1)
    is Err(ActiveExhausted),
  )
  assert_eq(ledger_usage(ledger_b), b_before)
  assert_eq(model_io_admission_counts(shared, installation), Some((1, 1)))
  // The physical ACK retires only active I/O. Store/Journal remains pending.
  settle_model_io_after_owner_ack(shared, installation, origin_a, a, 0, 1).unwrap()
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 1)))
  assert_true(holding_available(ledger_a, a.census.unwrap()))
  let b = claim_model_io_admission(shared, installation, origin_b, attempt_b, 0, 1).unwrap()
  assert_eq(model_io_admission_counts(shared, installation), Some((1, 2)))
  settle_model_io_after_owner_ack(shared, installation, origin_b, b, 0, 1).unwrap()
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 2)))
  let later = reserve_attempt(ledger_a, 1L, 10L, 10L).unwrap()
  let a_before = ledger_usage(ledger_a)
  assert_true(
    claim_model_io_admission(shared, installation, origin_a, later, 1, 1)
    is Err(HoldingExhausted),
  )
  assert_eq(ledger_usage(ledger_a), a_before)
  // Original Store/Journal confirmation plus actual alias cleanup is separate.
  settle_model_holding_after_owner_ack(shared, installation, origin_b, b, 0, 1).unwrap()
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 1)))
  let next = claim_model_io_admission(shared, installation, origin_a, later, 1, 1).unwrap()
  assert_eq(model_io_admission_counts(shared, installation), Some((1, 2)))
  settle_model_io_after_owner_ack(shared, installation, origin_a, next, 1, 1).unwrap()
  settle_model_holding_after_owner_ack(shared, installation, origin_a, next, 1, 1).unwrap()
  settle_model_holding_after_owner_ack(shared, installation, origin_a, a, 0, 1).unwrap()
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 0)))
  assert_true(close_model_io_admission(shared, installation).unwrap())
}

///|
test "Model shared tickets reject foreign installation admission Run slot and attempt" {
  let installation = Ref(0)
  let same_data_foreign = Ref(0)
  let shared = issue_model_io_admission(installation, 2, 2).unwrap()
  let foreign = issue_model_io_admission(installation, 2, 2).unwrap()
  let (ledger, origin, reservation) = model_io_test_run()
  let (_, other, other_reservation) = model_io_test_run()
  assert_true(
    claim_model_io_admission(shared, same_data_foreign, origin, reservation, 0, 1)
    is Err(ForeignInstallation),
  )
  assert_true(
    claim_model_io_admission(shared, installation, origin, other_reservation, 0, 1)
    is Err(ForeignTicket),
  )
  let ticket = claim_model_io_admission(shared, installation, origin, reservation, 0, 1).unwrap()
  assert_true(
    settle_model_io_after_owner_ack(foreign, installation, origin, ticket, 0, 1)
    is Err(ForeignTicket),
  )
  assert_true(
    settle_model_io_after_owner_ack(shared, installation, other, ticket, 0, 1)
    is Err(ForeignTicket),
  )
  assert_true(
    settle_model_io_after_owner_ack(shared, installation, origin, ticket, 1, 1)
    is Err(ForeignTicket),
  )
  assert_true(
    settle_model_io_after_owner_ack(shared, installation, origin, ticket, 0, 2)
    is Err(ForeignTicket),
  )
  let copied : ModelIoTicket[Ref[Int]] = { ..ticket, }
  assert_true(
    settle_model_io_after_owner_ack(shared, installation, origin, copied, 0, 1)
    is Err(ForeignTicket),
  )
  let inventory = ledger.original_inventory.unwrap()
  ledger.original_inventory = Some({ ..inventory, identity: other, })
  assert_true(
    settle_model_io_after_owner_ack(shared, installation, origin, ticket, 0, 1)
    is Err(ForeignTicket),
  )
  ledger.original_inventory = Some(inventory)
  let another_attempt = reserve_attempt(ledger, 1L, 10L, 10L).unwrap()
  ticket.reservation = Some(another_attempt)
  assert_true(
    settle_model_io_after_owner_ack(shared, installation, origin, ticket, 0, 1)
    is Err(ForeignTicket),
  )
  ticket.reservation = Some(reservation)
  assert_eq(model_io_admission_counts(shared, installation), Some((1, 1)))
  settle_model_io_after_owner_ack(shared, installation, origin, ticket, 0, 1).unwrap()
  settle_model_holding_after_owner_ack(shared, installation, origin, ticket, 0, 1).unwrap()
}

///|
test "Model shared tickets reject copied original identity duplicate attempt and double retirement" {
  let installation = Ref(0)
  let shared = issue_model_io_admission(installation, 4, 4).unwrap()
  let (_, origin, reservation) = model_io_test_run()
  let copied : OriginalLedgerIdentity = { ..origin, }
  assert_true(
    claim_model_io_admission(shared, installation, copied, reservation, 0, 1)
    is Err(ForeignTicket),
  )
  let ticket = claim_model_io_admission(shared, installation, origin, reservation, 0, 1).unwrap()
  assert_true(
    claim_model_io_admission(shared, installation, origin, reservation, 0, 1)
    is Err(DuplicateAttempt),
  )
  assert_true(
    claim_model_io_admission(shared, installation, origin, reservation, 1, 1)
    is Err(DuplicateAttempt),
  )
  assert_true(
    settle_model_holding_after_owner_ack(shared, installation, origin, ticket, 0, 1)
    is Err(CleanupPending),
  )
  settle_model_io_after_owner_ack(shared, installation, origin, ticket, 0, 1).unwrap()
  assert_true(
    settle_model_io_after_owner_ack(shared, installation, origin, ticket, 0, 1)
    is Err(IoAlreadyRetired),
  )
  settle_model_holding_after_owner_ack(shared, installation, origin, ticket, 0, 1).unwrap()
  assert_true(
    settle_model_holding_after_owner_ack(shared, installation, origin, ticket, 0, 1)
    is Err(TicketRetired),
  )
  assert_true(ticket.owner is None)
  assert_true(ticket.origin is None)
  assert_true(ticket.reservation is None)
  assert_true(ticket.census is None)
}

///|
test "Model closing admission drains the same tickets without cancellation or new borrowing" {
  let installation = Ref(0)
  let shared = issue_model_io_admission(installation, 2, 2).unwrap()
  let (_, origin, reservation) = model_io_test_run()
  let ticket = claim_model_io_admission(shared, installation, origin, reservation, 0, 1).unwrap()
  assert_false(close_model_io_admission(shared, installation).unwrap())
  assert_true(ticket.active)
  assert_true(
    claim_model_io_admission(shared, installation, origin, reservation, 1, 1)
    is Err(AdmissionClosing),
  )
  settle_model_io_after_owner_ack(shared, installation, origin, ticket, 0, 1).unwrap()
  assert_false(close_model_io_admission(shared, installation).unwrap())
  settle_model_holding_after_owner_ack(shared, installation, origin, ticket, 0, 1).unwrap()
  assert_true(close_model_io_admission(shared, installation).unwrap())
}

///|
test "Model shared obligation stays in the original zero byte census until actual retirement" {
  let installation = Ref(0)
  let shared = issue_model_io_admission(installation, 1, 1).unwrap()
  let (ledger, origin, reservation) = model_io_test_run()
  let ticket = claim_model_io_admission(shared, installation, origin, reservation, 0, 1).unwrap()
  // The original attempt settles; response/Unknown holding is still owned.
  settle_reservation(ledger, reservation).unwrap()
  assert_eq(ledger_usage(ledger).held_bytes, 0L)
  assert_false(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(model_io_admission_counts(shared, installation), Some((1, 1)))
  settle_model_io_after_owner_ack(shared, installation, origin, ticket, 0, 1).unwrap()
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 1)))
  assert_false(finish_original_ledger_inventory(ledger, true).unwrap())
  settle_model_holding_after_owner_ack(shared, installation, origin, ticket, 0, 1).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_false(original_ledger_inventory_live(origin))
}

///|
test "Model shared failed original census admission cannot consume global availability" {
  let installation = Ref(0)
  let shared = issue_model_io_admission(installation, 1, 1).unwrap()
  let ledger = create_ledger({
    planning_work: 4,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 10L,
    retained_bytes: 10L,
    execution_bytes: 10L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 1L, 1L).unwrap()
  let origin = begin_original_ledger_inventory(ledger, bootstrap, 1, 0, 0).unwrap()
  let reservation = reserve_attempt(ledger, 1L, 1L, 1L).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    claim_model_io_admission(shared, installation, origin, reservation, 0, 1)
    is Err(Resource(HoldingLimit)),
  )
  assert_eq(model_io_admission_counts(shared, installation), Some((0, 0)))
  assert_eq(ledger_usage(ledger), before)
  assert_true(shared.duties.is_empty())
}
