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
