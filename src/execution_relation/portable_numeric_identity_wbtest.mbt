// Retained independent pinned-core reference bits, run-J1dKXM.

///|
test "scalar Owner exact portable identity 0: exp" {
  match unary(@lower.Exp, Number(-373.8015018526243)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x1e3a538161077982UL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 1: ln" {
  match unary(@lower.Ln, Number(8.955102088495668)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x400189ac70cbeb70UL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 2: ln" {
  match unary(@lower.Ln, Number(0.7096359903413106)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0xbfd5f3c36686db50UL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 3: ln" {
  match unary(@lower.Ln, Number(43.64301119989392)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x400e35561db2a5acUL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 4: ln" {
  match unary(@lower.Ln, Number(93.3951804061785)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x401225b95140bd10UL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 5: ln" {
  match unary(@lower.Ln, Number(20.90108389454774)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x40085183324a30f2UL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 6: ln" {
  match unary(@lower.Ln, Number(43.83775473204472)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x400e3e7462d43664UL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 7: ln" {
  match unary(@lower.Ln, Number(1.4680892331809163)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x3fd892d42704dce1UL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 8: ln" {
  match unary(@lower.Ln, Number(1.2783106518366594)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x3fcf6dd5ccd22ff8UL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 9: log10" {
  match unary(@lower.Log10, Number(21.265579840947197)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x3ff53e2a7a60ad4fUL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 10: log10" {
  match unary(@lower.Log10, Number(2.8956631384538802)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x3fdd8d47a426e273UL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 11: log10" {
  match unary(@lower.Log10, Number(83.46167682682146)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x3ffebe694375ffd0UL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 12: log10" {
  match unary(@lower.Log10, Number(1.4680892331809163)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x3fc55824f76150adUL)
    _ => assert_true(false)
  }
}

///|
test "scalar Owner exact portable identity 13: pow" {
  match
    binary(@lower.Pow, Number(35.82791729235208), Number(15.398635423713735)) {
    Ok(Number(n)) => assert_eq(n.reinterpret_as_uint64(), 0x44e6ae0f50dde019UL)
    _ => assert_true(false)
  }
}
