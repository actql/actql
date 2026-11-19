///|
fn publication_scratch_fixture() -> (
  Ledger,
  PreparationCapacity[Array[Int], Array[Int]],
  Array[Int],
  PreparationBodyBorrow[Array[Int]],
) {
  let ledger = create_ledger({
    planning_work: 10,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 100L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let input = [1]
  let body = [2]
  let owner : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    60L,
    80L,
    max_borrowers=2,
  ).unwrap()
  complete_preparation_capacity(owner, input, body, 60L, 80L).unwrap()
  transfer_preparation_capacity_to_run(owner, input, body, ledger).unwrap()
  (ledger, owner, body, borrow_preparation_body(owner).unwrap())
}

///|
fn publication_scratch_origin(
  ledger : Ledger,
  current : (Int64) -> Int,
) -> ImportedChildLedgerOrigin {
  {
    nonce: 1L,
    admit: _ => 0,
    current,
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    acquire_window: None,
    acquiring_window: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  }
}

///|
test "returned publication scratch keeps original retention and exact execution admission" {
  let (ledger, owner, body, holder) = publication_scratch_fixture()
  let sibling = borrow_preparation_body_sibling(holder).unwrap()
  let token = owner.reservation.reservation
  let other = reserve_capacity(ledger, 10L, 20L).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    reconcile_preparation_publication_execution(holder, [2], 40L)
    is Err(ForeignOriginal),
  )
  assert_true(
    reconcile_preparation_publication_execution(holder, body, 81L)
    is Err(InvalidExtent),
  )
  reconcile_preparation_publication_execution(holder, body, 40L).unwrap()
  let after = ledger_usage(ledger)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.planning_work, before.planning_work)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_eq(after.reserved_execution_bytes, 60L)
  assert_true(physical_equal(token, owner.reservation.reservation))
  assert_true(
    physical_equal(preparation_body_borrow_value(sibling).unwrap(), body),
  )
  assert_true(reserve_capacity(ledger, 0L, 41L) is Err(ExecutionLimit))
  let exact = reserve_capacity(ledger, 0L, 40L).unwrap()
  settle_capacity(ledger, exact).unwrap()
  settle_capacity(ledger, other).unwrap()
  assert_false(retire_preparation_capacity(owner).unwrap())
  assert_false(return_preparation_body_borrow(holder).unwrap())
  assert_true(return_preparation_body_borrow(sibling).unwrap())
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "publication scratch current loss keeps debit and reentry cannot replace its owner" {
  let (ledger, owner, body, holder) = publication_scratch_fixture()
  let mode = Ref(1)
  let observed = Ref(0)
  ledger.imported_child = Some(
    publication_scratch_origin(ledger, _ => {
      if mode.val == 1 {
        mode.val = 0
        if reconcile_preparation_publication_execution(holder, body, 20L)
          is Err(WorkActive) {
          observed.val += 1
        }
        if reserve_preparation_publication_phase(holder, body, 60L, 90L)
          is Err(WorkActive) {
          observed.val += 1
        }
        if retire_preparation_capacity(owner) is Err(WorkActive) {
          observed.val += 1
        }
      }
      if mode.val == 2 {
        1
      } else {
        0
      }
    }),
  )
  reconcile_preparation_publication_execution(holder, body, 40L).unwrap()
  assert_eq(observed.val, 3)
  let before = ledger_usage(ledger)
  mode.val = 2
  assert_true(
    reconcile_preparation_publication_execution(holder, body, 20L)
    is Err(Resource(ClosedReservation)),
  )
  assert_eq(ledger_usage(ledger), before)
  mode.val = 0
  assert_false(retire_preparation_capacity(owner).unwrap())
  assert_true(return_preparation_body_borrow(holder).unwrap())
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "publication scratch cannot refund after its selected borrower is consumed during current" {
  let (ledger, owner, body, holder) = publication_scratch_fixture()
  let sibling = borrow_preparation_body_sibling(holder).unwrap()
  let armed = Ref(true)
  ledger.imported_child = Some(
    publication_scratch_origin(ledger, _ => {
      if armed.val {
        armed.val = false
        return_preparation_body_borrow(holder).unwrap() |> ignore
      }
      0
    }),
  )
  let before = ledger_usage(ledger)
  assert_true(
    reconcile_preparation_publication_execution(holder, body, 40L)
    is Err(BorrowReturned),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(
    physical_equal(preparation_body_borrow_value(sibling).unwrap(), body),
  )
  assert_false(retire_preparation_capacity(owner).unwrap())
  assert_true(return_preparation_body_borrow(sibling).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}
