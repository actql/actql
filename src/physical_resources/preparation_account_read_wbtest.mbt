///|
test "Account child Read preserves Ready and blocks same parent retirement until actual cleanup" {
  let (ledger, owner, input) = construction_input_fixture()
  complete_preparation_capacity(owner, input, [2], 20L, 10L).unwrap()
  let read = prepare_account_read(owner, input, 64L).unwrap()
  prepare_account_read_construction(read, 200L, 300L).unwrap()
  assert_true(owner.phase == Ready)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 220L)
  assert_false(retire_preparation_capacity(owner).unwrap())
  assert_false(close_preparation_account_read(read, false).unwrap())
  assert_true(
    prepare_account_read_construction(read, 201L, 301L) is Err(Retired),
  )
  assert_true(close_preparation_account_read(read, true).unwrap())
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}

///|
test "Account child sums siblings and refuses foreign and insufficient original before construction" {
  let (ledger, owner, input) = construction_input_fixture()
  assert_true(prepare_account_read(owner, [1], 64L) is Err(ForeignOriginal))
  let first = prepare_account_read(owner, input, 64L).unwrap()
  let second = prepare_account_read(owner, input, 64L).unwrap()
  prepare_account_read_construction(first, 600L, 600L).unwrap()
  assert_true(
    prepare_account_read_construction(second, 500L, 500L)
    is Err(Resource(RetentionLimit)),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 684L)
  assert_false(close_preparation_account_read(first, false).unwrap())
  assert_true(close_preparation_account_read(second, true).unwrap())
  assert_true(close_preparation_account_read(first, true).unwrap())
  abort_preparation_capacity_after_cleanup(owner, input).unwrap() |> ignore
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}

///|
test "completed Account construction keeps retained DATA and permits the next sibling workspace" {
  let (ledger, owner, input) = construction_input_fixture()
  let first = prepare_account_read(owner, input, 64L).unwrap()
  prepare_account_read_construction(first, 200L, 700L).unwrap()
  complete_account_read_construction(first).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 220L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 210L)
  assert_eq(ledger_usage(ledger).live_reservations, 2)
  assert_eq(owner.borrowers, 1)
  let second = prepare_account_read(owner, input, 64L).unwrap()
  prepare_account_read_construction(second, 200L, 700L).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 910L)
  assert_true(
    complete_account_read_construction(first) is Err(AlreadyCompleted),
  )
  assert_true(
    prepare_account_read_construction(first, 201L, 201L) is Err(Retired),
  )
  assert_false(close_preparation_account_read(first, false).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 420L)
  close_preparation_account_read(first, true).unwrap() |> ignore
  close_preparation_account_read(second, true).unwrap() |> ignore
  abort_preparation_capacity_after_cleanup(owner, input).unwrap() |> ignore
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}

///|
test "failed or retiring Account construction never spends the retained scratch peak" {
  let (ledger, owner, input) = construction_input_fixture()
  complete_preparation_capacity(owner, input, [2], 20L, 10L).unwrap()
  let first = prepare_account_read(owner, input, 64L).unwrap()
  let failed = prepare_account_read(owner, input, 64L).unwrap()
  prepare_account_read_construction(first, 200L, 700L).unwrap()
  assert_true(
    prepare_account_read_construction(failed, 200L, 700L)
    is Err(Resource(ExecutionLimit)),
  )
  let before = ledger_usage(ledger)
  assert_true(complete_account_read_construction(failed) is Err(Retired))
  assert_eq(ledger_usage(ledger), before)
  assert_false(retire_preparation_capacity(owner).unwrap())
  assert_true(complete_account_read_construction(first) is Err(Retired))
  assert_eq(
    ledger_usage(ledger).reserved_execution_bytes,
    before.reserved_execution_bytes,
  )
  close_preparation_account_read(failed, true).unwrap() |> ignore
  close_preparation_account_read(first, true).unwrap() |> ignore
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}

///|
test "Account completion current callback cannot retire the parent and refund its scratch" {
  let (ledger, owner, input) = construction_input_fixture()
  complete_preparation_capacity(owner, input, [2], 20L, 10L).unwrap()
  let read = prepare_account_read(owner, input, 64L).unwrap()
  prepare_account_read_construction(read, 200L, 700L).unwrap()
  let reenter = Ref(true)
  let retired = Ref(false)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if reenter.val {
        reenter.val = false
        retired.val = retire_preparation_capacity(owner) == Ok(false)
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
    acquire_window: None,
    acquiring_window: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_true(complete_account_read_construction(read) is Err(Retired))
  assert_true(retired.val)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 710L)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 220L)
  close_preparation_account_read(read, true).unwrap() |> ignore
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}
