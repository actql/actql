// Exact portable-algorithm reference bits from the retained independent
// pinned-core Native diagnostic run-J1dKXM; not product-generated expectations.

///|
test "portable numeric identity counterexample 0: exp" {
  assert_eq(
    exp(-373.8015018526243).reinterpret_as_uint64(),
    0x1e3a538161077982UL,
  )
}

///|
test "portable numeric identity counterexample 1: ln" {
  assert_eq(ln(8.955102088495668).reinterpret_as_uint64(), 0x400189ac70cbeb70UL)
}

///|
test "portable numeric identity counterexample 2: ln" {
  assert_eq(
    ln(0.7096359903413106).reinterpret_as_uint64(),
    0xbfd5f3c36686db50UL,
  )
}

///|
test "portable numeric identity counterexample 3: ln" {
  assert_eq(ln(43.64301119989392).reinterpret_as_uint64(), 0x400e35561db2a5acUL)
}

///|
test "portable numeric identity counterexample 4: ln" {
  assert_eq(ln(93.3951804061785).reinterpret_as_uint64(), 0x401225b95140bd10UL)
}

///|
test "portable numeric identity counterexample 5: ln" {
  assert_eq(ln(20.90108389454774).reinterpret_as_uint64(), 0x40085183324a30f2UL)
}

///|
test "portable numeric identity counterexample 6: ln" {
  assert_eq(ln(43.83775473204472).reinterpret_as_uint64(), 0x400e3e7462d43664UL)
}

///|
test "portable numeric identity counterexample 7: ln" {
  assert_eq(
    ln(1.4680892331809163).reinterpret_as_uint64(),
    0x3fd892d42704dce1UL,
  )
}

///|
test "portable numeric identity counterexample 8: ln" {
  assert_eq(
    ln(1.2783106518366594).reinterpret_as_uint64(),
    0x3fcf6dd5ccd22ff8UL,
  )
}

///|
test "portable numeric identity counterexample 9: log10" {
  assert_eq(
    log10(21.265579840947197).reinterpret_as_uint64(),
    0x3ff53e2a7a60ad4fUL,
  )
}

///|
test "portable numeric identity counterexample 10: log10" {
  assert_eq(
    log10(2.8956631384538802).reinterpret_as_uint64(),
    0x3fdd8d47a426e273UL,
  )
}

///|
test "portable numeric identity counterexample 11: log10" {
  assert_eq(
    log10(83.46167682682146).reinterpret_as_uint64(),
    0x3ffebe694375ffd0UL,
  )
}

///|
test "portable numeric identity counterexample 12: log10" {
  assert_eq(
    log10(1.4680892331809163).reinterpret_as_uint64(),
    0x3fc55824f76150adUL,
  )
}

///|
test "portable numeric identity counterexample 13: pow" {
  assert_eq(
    pow(35.82791729235208, 15.398635423713735).reinterpret_as_uint64(),
    0x44e6ae0f50dde019UL,
  )
}
