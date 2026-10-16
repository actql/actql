///|
test "imported child ledger unsupported target has no scalar or callback admission" {
  assert_true(prepare_imported_child_ledger(7L) is Err(Unavailable))
  assert_true(prepare_imported_child_ledger(0L) is Err(InvalidOriginal))
}
