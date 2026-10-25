///|
test "publication phase preserves same token exact capacity and all borrower retirement" {
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
    30L,
    10L,
    max_borrowers=2,
  ).unwrap()
  complete_preparation_capacity(owner, input, body, 30L, 0L).unwrap()
  transfer_preparation_capacity_to_run(owner, input, body, ledger).unwrap()
  let first = borrow_preparation_capacity(owner).unwrap()
  let second = borrow_preparation_capacity(owner).unwrap()
  let token = owner.reservation.reservation
  let other = reserve_capacity(ledger, 10L, 10L).unwrap()
  assert_true(
    reserve_preparation_publication_phase(owner, input, body, 91L, 90L)
    is Err(Resource(RetentionLimit)),
  )
  assert_true(
    reserve_preparation_publication_phase(owner, input, body, 90L, 91L)
    is Err(Resource(ExecutionLimit)),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 40L)
  reserve_preparation_publication_phase(owner, input, body, 90L, 90L).unwrap()
  assert_true(physical_equal(token, owner.reservation.reservation))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 100L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 100L)
  assert_true(
    reserve_preparation_publication_phase(owner, input, [2], 90L, 90L)
    is Err(ForeignOriginal),
  )
  assert_true(
    reserve_preparation_publication_phase(owner, [1], body, 90L, 90L)
    is Err(ForeignOriginal),
  )
  assert_true(
    reserve_preparation_publication_phase(owner, input, body, 89L, 90L)
    is Err(InvalidExtent),
  )
  assert_false(retire_preparation_capacity(owner).unwrap())
  assert_false(return_preparation_capacity_borrow(first).unwrap())
  assert_true(return_preparation_capacity_borrow(second).unwrap())
  settle_capacity(ledger, other).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "publication phase latches reentry and rejects stopped original growth" {
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
    30L,
    10L,
    max_borrowers=2,
  ).unwrap()
  complete_preparation_capacity(owner, input, body, 30L, 0L).unwrap()
  transfer_preparation_capacity_to_run(owner, input, body, ledger).unwrap()
  let holder = borrow_preparation_capacity(owner).unwrap()
  let mode = Ref::new(1)
  let observed = Ref::new(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if mode.val == 1 {
        mode.val = 0
        if reserve_preparation_publication_phase(owner, input, body, 50L, 20L)
          is Err(WorkActive) {
          observed.val += 1
        }
        if retire_preparation_capacity(owner) is Err(WorkActive) {
          observed.val += 1
        }
        if borrow_preparation_capacity(owner) is Err(Retired) {
          observed.val += 1
        }
      }
      if mode.val == 2 {
        1
      } else {
        0
      }
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  reserve_preparation_publication_phase(owner, input, body, 50L, 20L).unwrap()
  assert_eq(observed.val, 3)
  mode.val = 2
  assert_true(
    reserve_preparation_publication_phase(owner, input, body, 50L, 20L)
    is Err(Resource(ClosedReservation)),
  )
  assert_true(
    reserve_preparation_publication_phase(owner, input, body, 51L, 21L)
    is Err(Resource(ClosedReservation)),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 50L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 20L)
  assert_false(retire_preparation_capacity(owner).unwrap())
  assert_true(return_preparation_capacity_borrow(holder).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "publication phase cannot construct after callback cuts last original borrower" {
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
    30L,
    10L,
    max_borrowers=1,
  ).unwrap()
  complete_preparation_capacity(owner, input, body, 30L, 0L).unwrap()
  assert_true(
    reserve_preparation_publication_phase(owner, input, body, 50L, 20L)
    is Err(WorkActive),
  )
  transfer_preparation_capacity_to_run(owner, input, body, ledger).unwrap()
  let holder = borrow_preparation_capacity(owner).unwrap()
  let armed = Ref::new(true)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if armed.val {
        armed.val = false
        ignore(return_preparation_capacity_borrow(holder))
      }
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_true(
    reserve_preparation_publication_phase(owner, input, body, 50L, 20L)
    is Err(WorkActive),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 50L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 20L)
  assert_true(retire_preparation_capacity(owner).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}
