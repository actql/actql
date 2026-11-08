///|
// ABI/constructor geometry only. No Library, Read, Journal or physical backing
// is acquired by this test; the ordinary callback/custody route is separate.
test "Native journal writer raw request follows the pinned builder capacity" {
  let (header, unit, _, _, _) = @bootstrap.native_managed_value_layout()
  let (retained, execution, raw) = journal_row_construction_working(257, 16, 2).unwrap()
  assert_eq(retained, 273L)
  assert_true(execution > retained)
  assert_eq(raw, header + 513L * unit)
  assert_eq(journal_row_construction_working(-1, 16, 2), None)
  assert_eq(journal_row_construction_working(257, 0, 2), None)
  // Native Int overflow falls back to the actual required capacity rather
  // than quoting a capacity that the pinned StringBuilder never constructs.
  let (_, _, large) = journal_row_construction_working(1073741825, 16, 2).unwrap()
  assert_eq(large, header + 1073741826L * unit)
}

///|
test "Native journal construction separates returned wire from simultaneous scratch" {
  let bytes = 2 * 1048576
  let (retained, execution, raw) = journal_row_construction_working(
    bytes, 16, 2,
  ).unwrap()
  assert_eq(retained, bytes.to_int64() + 16L)
  // Existing Read retention is not inflated by the old/new UTF16 buffers.
  // Those complete buffers/finish String still belong to execution pricing.
  assert_true(retained < 3L * 1048576L)
  assert_true(execution > 6L * bytes.to_int64())
  let (header, unit, _, _, _) = @bootstrap.native_managed_value_layout()
  assert_eq(raw, header + (bytes.to_int64() + 1L) * unit)
}
