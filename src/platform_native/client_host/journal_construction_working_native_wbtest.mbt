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

///|
test "Native journal selected record policy exceeds 1024 without changing finite limits" {
  for maximum in [1023, 1024, 1025, 2147483647] {
    assert_true(valid_local_journal_options(1000.0, maximum, 1048576L))
    let count = Int64::min(maximum.to_int64() * 64L, 2147483647L).to_int()
    assert_true(
      local_journal_related_issuance_count(
        @utf8.encode(count.to_string()),
        count.to_int64(),
        maximum,
      )
      is Ok(actual) &&
      actual == count,
    )
  }
  assert_false(valid_local_journal_options(1000.0, 0, 1048576L))
  assert_false(valid_local_journal_options(1000.0, -1, 1048576L))
  assert_false(valid_local_journal_options(0.0, 1025, 1048576L))
  assert_false(valid_local_journal_options(1000.0, 1025, 536870913L))
  assert_true(
    local_journal_related_issuance_count(b"100000", 100000L, 2000) is Ok(actual) &&
    actual == 100000,
  )
  assert_true(
    local_journal_related_issuance_count(b"2147483647", 2147483647L, 2147483647)
    is Ok(actual) &&
    actual == 2147483647,
  )
  for
    body in [
      b"", b"00", b"-1", b"+1", b"65537", b"2147483648", b"999999999999999999",
    ] {
    assert_true(
      local_journal_related_issuance_count(body, 0L, 1024) is Err(CustodyLost),
    )
  }
  assert_true(
    local_journal_related_issuance_count(b"65536", 65535L, 1024)
    is Err(CustodyLost),
  )
}

///|
test "Native related journal append refuses actual counter exhaustion before wrap" {
  assert_true(local_journal_related_append_available(65535, 1024))
  assert_false(local_journal_related_append_available(65536, 1024))
  assert_true(local_journal_related_append_available(65536, 1025))
  assert_true(local_journal_related_append_available(2147483646, 2147483647))
  assert_false(local_journal_related_append_available(2147483647, 2147483647))
  assert_false(local_journal_related_append_available(-1, 1025))
  assert_false(local_journal_related_append_available(0, 0))
}
