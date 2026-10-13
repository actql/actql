///|
test "Native diagnostic omission is fixed and preserves Physical classification" {
  assert_eq(decode_diagnostic(b""), "SQLite diagnostic detail omitted")
  assert_eq(decode_diagnostic(b"abc"), "abc")
  assert_eq(decode_diagnostic(b"\xc3\xa9"), "é")
  assert_true(Physical(decode_diagnostic(b"")) is Physical(_))
  assert_true(
    load_library("unused", diagnostic_ceiling=Some(0)) is Err(InvalidLimit),
  )
  assert_true(
    load_library("unused", diagnostic_ceiling=Some(-1)) is Err(InvalidLimit),
  )
}
