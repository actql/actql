///|
test "Signature explicit diagnostic limit refuses before physical loading" {
  assert_true(
    load_library("unused", diagnostic_ceiling=Some(0)) is Err(InvalidInput),
  )
  assert_true(
    load_library("unused", diagnostic_ceiling=Some(-1)) is Err(InvalidInput),
  )
}
