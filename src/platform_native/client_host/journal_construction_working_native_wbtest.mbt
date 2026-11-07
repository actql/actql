///|
// ABI/constructor geometry only. No Library, Read, Journal or physical backing
// is acquired by this test; the ordinary callback/custody route is separate.
test "Native journal writer raw request follows the pinned builder capacity" {
  let (header, unit, _, _, _) = @bootstrap.native_managed_value_layout()
  let (logical, raw) = journal_row_construction_working(257, 16, 2).unwrap()
  assert_true(logical > 257L)
  assert_eq(raw, header + 513L * unit)
  assert_eq(journal_row_construction_working(-1, 16, 2), None)
  assert_eq(journal_row_construction_working(257, 0, 2), None)
  // Native Int overflow falls back to the actual required capacity rather
  // than quoting a capacity that the pinned StringBuilder never constructs.
  let (_, large) = journal_row_construction_working(1073741825, 16, 2).unwrap()
  assert_eq(large, header + 1073741826L * unit)
}
