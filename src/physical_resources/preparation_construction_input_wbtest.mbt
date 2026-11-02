///|
fn construction_input_fixture(
  max_borrowers? : Int = 3,
) -> (Ledger, PreparationCapacity[Array[Int], Array[Int]], Array[Int]) {
  let ledger = create_ledger({
    planning_work: 10,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 100L,
    retained_bytes: 1000L,
    execution_bytes: 1000L,
  }).unwrap()
  let input = [1]
  let owner : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    20L,
    10L,
    max_borrowers~,
  ).unwrap()
  (ledger, owner, input)
}

///|
test "construction input uses the same slots across working complete Run retirement and actual returns" {
  let (ledger, owner, input) = construction_input_fixture()
  let data = ["original compiler"]
  assert_true(borrow_preparation_body(owner) is Err(Retired))
  let holder = reserve_preparation_construction_input(
    owner, input, data, 100L, 80L,
  ).unwrap()
  assert_true(owner.body is None && owner.borrowers == 1)
  assert_true(
    physical_equal(preparation_body_borrow_value(holder).unwrap(), data),
  )
  assert_false(preparation_body_usage_isolated(holder, ledger))
  assert_true(
    (holder.reserve_publication_original)(data, 100L, 80L)
    is Err(ForeignOriginal),
  )
  assert_true(
    transfer_preparation_capacity_to_run(owner, input, [2], ledger)
    is Err(ForeignOriginal),
  )
  let final_body = [2]
  complete_preparation_capacity(owner, input, final_body, 60L, 20L).unwrap()
  transfer_preparation_capacity_to_run(owner, input, final_body, ledger).unwrap()
  let body = borrow_preparation_body(owner).unwrap()
  assert_true(
    physical_equal(preparation_body_borrow_value(body).unwrap(), final_body),
  )
  assert_true(
    physical_equal(preparation_body_borrow_value(holder).unwrap(), data),
  )
  assert_false(retire_preparation_capacity(owner).unwrap())
  assert_true(preparation_body_retirement_started(holder))
  assert_true(borrow_preparation_body_sibling(holder) is Err(Retired))
  assert_false(return_preparation_body_borrow(holder).unwrap())
  assert_true(preparation_body_borrow_value(holder) is None)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 60L)
  assert_true(return_preparation_body_borrow(body).unwrap())
  assert_eq(ledger_usage(ledger).live_reservations, 0)
  assert_true(return_preparation_body_borrow(holder) is Err(BorrowReturned))
}

///|
test "construction input reserve and borrow observes current once and immutable reads observe none" {
  let (ledger, owner, input) = construction_input_fixture(max_borrowers=2)
  let calls = Ref(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_true(
    reserve_preparation_construction_input(owner, [1], ["foreign"], 100L, 80L)
    is Err(ForeignOriginal),
  )
  assert_eq(calls.val, 0)
  let data = ["compiled"]
  let holder = reserve_preparation_construction_input(
    owner, input, data, 100L, 80L,
  ).unwrap()
  assert_eq(calls.val, 1)
  for _ in 0..<8 {
    assert_true(
      physical_equal(preparation_body_borrow_value(holder).unwrap(), data),
    )
    assert_eq(preparation_body_borrow_reserved_extents(holder), Ok((100L, 80L)))
  }
  assert_eq(calls.val, 1)
  let sibling = borrow_preparation_body_sibling(holder).unwrap()
  assert_eq(calls.val, 2)
  assert_true(borrow_preparation_body_sibling(holder) is Err(InvalidExtent))
  assert_eq(calls.val, 2)
  assert_false(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 100L)
  assert_false(return_preparation_body_borrow(sibling).unwrap())
  assert_true(return_preparation_body_borrow(holder).unwrap())
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}

///|
test "construction input failed grow and retired reentrant borrow preserve one original debit" {
  let (ledger, owner, input) = construction_input_fixture(max_borrowers=2)
  assert_true(
    reserve_preparation_construction_input(owner, input, ["x"], 1001L, 80L)
    is Err(Resource(RetentionLimit)),
  )
  assert_eq(owner.borrowers, 0)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 20L)
  let holder = reserve_preparation_construction_input(
    owner,
    input,
    ["compiled"],
    100L,
    80L,
  ).unwrap()
  let observations = Ref(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if owner.borrowers == 2 {
        observations.val += 1
      }
      if borrow_preparation_body_sibling(holder) is Err(InvalidExtent) {
        observations.val += 1
      }
      if abort_preparation_capacity_after_cleanup(owner, input) == Ok(false) {
        observations.val += 1
      }
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_true(borrow_preparation_body_sibling(holder) is Err(Retired))
  assert_eq(observations.val, 3)
  assert_eq(owner.borrowers, 1)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 100L)
  ledger.imported_child = None
  assert_true(return_preparation_body_borrow(holder).unwrap())
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}
