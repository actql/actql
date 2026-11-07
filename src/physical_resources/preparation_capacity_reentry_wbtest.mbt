///|
test "preparation currentness reentry cannot bypass borrower slots or settle twice" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let input = [1]
  let owner : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    20L,
    max_borrowers=1,
  ).unwrap()
  complete_preparation_capacity(owner, input, [2], 30L, 0L).unwrap()
  let mode = Ref(1)
  let observations = Ref(0)
  let origin : ImportedChildLedgerOrigin = {
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if mode.val == 1 {
        mode.val = 0
        if borrow_preparation_capacity(owner) is Err(InvalidExtent) {
          observations.val += 1
        }
        if retire_preparation_capacity(owner) == Ok(false) {
          observations.val += 1
        }
      } else if mode.val == 2 {
        mode.val = 0
        if retire_preparation_capacity(owner) is Err(WorkActive) {
          observations.val += 1
        }
      }
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  }
  ledger.imported_child = Some(origin)
  assert_true(borrow_preparation_capacity(owner) is Err(Retired))
  assert_eq(observations.val, 2)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 30L)
  mode.val = 2
  assert_true(retire_preparation_capacity(owner).unwrap())
  assert_eq(observations.val, 3)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "preparation retirement failure clears owned references but never refunds unresolved debit" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let input = [1]
  let owner : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    20L,
    max_borrowers=1,
  ).unwrap()
  complete_preparation_capacity(owner, input, [2], 30L, 0L).unwrap()
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => -41,
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_true(
    retire_preparation_capacity(owner) is Err(Resource(ChildFundingUnavailable)),
  )
  assert_true(owner.body is None)
  assert_true(owner.input is None)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 30L)
  assert_true(
    retire_preparation_capacity(owner) is Err(Resource(ChildFundingUnavailable)),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 30L)
  assert_true(owner.phase == Retiring)
}

///|
test "preparation phase growth respects other holdings and stopping never authorizes transfer" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let input = [1]
  let body = [2]
  let owner : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    20L,
    max_borrowers=1,
  ).unwrap()
  complete_preparation_capacity(owner, input, body, 30L, 0L).unwrap()
  let other = reserve_capacity(ledger, 40L, 10L).unwrap()
  assert_true(
    begin_preparation_capacity_phase(owner, input, body, 70L, 50L)
    is Err(Resource(RetentionLimit)),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 70L)
  settle_capacity(ledger, other).unwrap()
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => 1,
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_true(
    transfer_preparation_capacity_to_run(owner, input, body, ledger)
    is Err(Resource(ClosedReservation)),
  )
  assert_true(
    begin_preparation_capacity_phase(owner, input, body, 70L, 50L)
    is Err(Resource(ClosedReservation)),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 30L)
  // Stopping prevents new allocation/adoption but permits original cleanup.
  assert_true(retire_preparation_capacity(owner).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "preparation same-token resize permits shrink but neither growth dimension after stopping" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let capacity = reserve_capacity(ledger, 40L, 20L).unwrap()
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => 1,
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_eq(
    resize_capacity_reservation(ledger, capacity, 39L, 21L),
    Err(ClosedReservation),
  )
  assert_eq(
    resize_capacity_reservation(ledger, capacity, 41L, 19L),
    Err(ClosedReservation),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 40L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 20L)
  resize_capacity_reservation(ledger, capacity, 30L, 10L).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 30L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 10L)
  settle_capacity(ledger, capacity).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}
