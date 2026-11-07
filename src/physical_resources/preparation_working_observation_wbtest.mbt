///|
test "working debit DATA is callback free and same selected parent current is checked once" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 2000L,
    execution_bytes: 2000L,
  }).unwrap()
  let input = [1]
  let prefix : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    500L,
    600L,
    max_borrowers=1,
  ).unwrap()
  let owner : PreparationCapacity[Array[Int], Bool] = continue_preparation_capacity(
    prefix, input,
  ).unwrap()
  let calls = Ref(0)
  let fenced = Ref(false)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      fenced.val = check_working_preparation_capacity_current(owner, input)
        is Err(WorkActive)
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
  assert_eq(
    preparation_capacity_working_extents(owner, input),
    Ok((500L, 600L)),
  )
  assert_eq(calls.val, 0)
  assert_true(
    preparation_capacity_working_extents(owner, [1]) is Err(ForeignOriginal),
  )
  let before = ledger_usage(ledger)
  check_working_preparation_capacity_current(owner, input).unwrap()
  assert_eq(calls.val, 1)
  assert_true(fenced.val && owner.phase == SelectedWorking)
  assert_eq(ledger_usage(ledger), before)
  ledger.imported_child = None
  assert_true(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
}

///|
test "new constructor current fence retains selected original debit on callback census closure" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 2000L,
    execution_bytes: 2000L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 100L, 1L).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, 1, 0, 0).unwrap() |> ignore
  let input = [1]
  let prefix : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    500L,
    600L,
    max_borrowers=1,
  ).unwrap()
  let owner : PreparationCapacity[Array[Int], Bool] = continue_preparation_capacity(
    prefix, input,
  ).unwrap()
  let calls = Ref(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      finish_original_ledger_inventory(ledger, false).unwrap() |> ignore
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
  let before = ledger_usage(ledger)
  assert_true(
    check_working_preparation_capacity_current(owner, input)
    is Err(Resource(ClosedReservation)),
  )
  assert_eq(calls.val, 1)
  assert_true(owner.phase == SelectedWorking && owner.input is Some(_))
  assert_eq(ledger_usage(ledger), before)
  ledger.imported_child = None
  assert_true(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}
