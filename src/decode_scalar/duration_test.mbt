///|
test "duration units and lexical normalization" {
  for
    (text, expected) in [
      ("1ms", 1L),
      ("001MS", 1L),
      ("1s", 1000L),
      ("01S", 1000L),
      ("2m", 120000L),
      ("3H", 10800000L),
      ("4d", 345600000L),
    ] {
    assert_eq(read_duration_ms(text), Some(expected))
  }
  for
    text in [
      "", "ms", "0ms", "000s", "-1s", "+1s", "1.5s", "1e3ms", " 1s", "1s ", "1 s",
      "１s", "١s", "1w", "1sec", "1s\n",
    ] {
    assert_eq(read_duration_ms(text), None)
  }
}

///|
test "duration multiplication respects exact safe integer endpoints" {
  for
    (unit, factor) in [
      ("ms", 1L),
      ("s", 1000L),
      ("m", 60000L),
      ("h", 3600000L),
      ("d", 86400000L),
    ] {
    let cap = 9007199254740991L / factor
    assert_eq(read_duration_ms(cap.to_string() + unit), Some(cap * factor))
    assert_eq(read_duration_ms((cap + 1L).to_string() + unit), None)
    assert_eq(
      read_duration_ms("000" + cap.to_string() + unit),
      Some(cap * factor),
    )
  }
  assert_eq(read_duration_ms("999999999999999999999999999999d"), None)
  assert_eq(read_duration_ms("0".repeat(10000) + "1s"), Some(1000L))
}
