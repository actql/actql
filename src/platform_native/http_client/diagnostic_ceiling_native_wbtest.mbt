///|
test "HTTP explicit diagnostic limit refuses before physical loading" {
  assert_true(
    load_library("unused", diagnostic_ceiling=Some(0))
    is Err(InvalidConfiguration),
  )
  assert_true(
    load_library("unused", diagnostic_ceiling=Some(-1))
    is Err(InvalidConfiguration),
  )
  assert_eq(decode_diagnostic(b""), "HTTP diagnostic detail omitted")
  assert_eq(decode_diagnostic(b"\xc3\xa9"), "é")
  assert_true(Transport(decode_diagnostic(b"")) is Transport(_))
}
