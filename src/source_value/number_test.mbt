///|
// Fixed expected binary64 words independently evaluated with ECMAScript JSON.parse.
// Exact halfway decimal cases distinguish nearest-even from truncation or ties-away.
test "JSON decimal tokens round to nearest even binary64 across targets" {
  for
    (text, bits) in [
      ("0", 0x0000000000000000UL),
      ("1", 0x3ff0000000000000UL),
      ("-1", 0xbff0000000000000UL),
      ("1.0", 0x3ff0000000000000UL),
      ("1e0", 0x3ff0000000000000UL),
      ("1E+3", 0x408f400000000000UL),
      ("-2.5", 0xc004000000000000UL),
      ("0.1", 0x3fb999999999999aUL),
      ("0.10000000000000001", 0x3fb999999999999aUL),
      ("0.10000000000000002", 0x3fb999999999999bUL),
      ("1e-7", 0x3e7ad7f29abcaf48UL),
      ("1e21", 0x444b1ae4d6e2ef50UL),
      ("9007199254740991", 0x433fffffffffffffUL),
      ("9007199254740992", 0x4340000000000000UL),
      ("9007199254740993", 0x4340000000000000UL),
      ("9007199254740995", 0x4340000000000002UL),
      ("18446744073709551616", 0x43f0000000000000UL),
      (
        "1.00000000000000011102230246251565404236316680908203125", 0x3ff0000000000000UL,
      ),
      (
        "1.00000000000000033306690738754696212708950042724609375", 0x3ff0000000000002UL,
      ),
      ("5e-324", 0x0000000000000001UL),
      ("2.4703282292062327e-324", 0x0000000000000000UL),
      ("2.4703282292062328e-324", 0x0000000000000001UL),
      ("-5e-324", 0x8000000000000001UL),
      ("2.2250738585072014e-308", 0x0010000000000000UL),
      ("2.2250738585072011e-308", 0x000fffffffffffffUL),
      ("1.7976931348623157e308", 0x7fefffffffffffffUL),
      ("1.7976931348623158e308", 0x7fefffffffffffffUL),
      ("1e-400", 0x0000000000000000UL),
      ("0e9999", 0x0000000000000000UL),
    ] {
    guard parsed(text).value is Number(number) else { fail("expected number") }
    assert_eq(number.reinterpret_as_uint64(), bits)
    guard parse_json_bytes(@utf8.encode(text), limits()).unwrap().value
      is Number(from_bytes) else {
      fail("expected number from bytes")
    }
    assert_eq(from_bytes.reinterpret_as_uint64(), bits)
  }
}

///|
test "long fractional significands do not cancel a truncated exponent" {
  let text = "0." + "0".repeat(65535) + "1e655360"
  assert_eq(rejected(text).issue, NumberOutOfRange)
  assert_eq(rejected("-" + text).issue, NumberOutOfRange)
  for zeroes in [65534, 65535, 65536, 65537, 100000] {
    let fractional = "0." + "0".repeat(zeroes) + "1"
    let integer = "1" + "0".repeat(zeroes)
    for
      (source, expected) in [
        (fractional + "e" + (zeroes + 1).to_string(), 1.0),
        (fractional + "e" + (zeroes + 2).to_string(), 10.0),
        (integer + "e-" + zeroes.to_string(), 1.0),
        (integer + "e-" + (zeroes + 1).to_string(), 0.1),
        (integer + "e-" + (zeroes + 400).to_string(), 0.0),
      ] {
      guard parsed(source).value is Number(number) else {
        fail("expected number")
      }
      assert_eq(
        number.reinterpret_as_uint64(),
        expected.reinterpret_as_uint64(),
      )
      guard parse_json_bytes(@utf8.encode(source), limits()).unwrap().value
        is Number(from_bytes) else {
        fail("expected byte input number")
      }
      assert_eq(
        from_bytes.reinterpret_as_uint64(),
        expected.reinterpret_as_uint64(),
      )
    }
    assert_eq(
      rejected(fractional + "e" + (zeroes + 310).to_string()).issue,
      NumberOutOfRange,
    )
    assert_eq(
      rejected("-" + integer + "e-" + (zeroes + 400).to_string()).issue,
      NegativeZero,
    )
  }
}

///|
test "huge exponents saturate only beyond possible mantissa cancellation" {
  let huge = "9".repeat(10000)
  for zero in ["0", "0.00000"] {
    assert_true(parsed(zero + "e" + huge).value is Number(0.0))
    assert_true(parsed(zero + "e-" + huge).value is Number(0.0))
    assert_eq(rejected("-" + zero + "e" + huge).issue, NegativeZero)
  }
  assert_eq(rejected("1e" + huge).issue, NumberOutOfRange)
  assert_true(parsed("1e-" + huge).value is Number(0.0))
  assert_eq(rejected("-1e-" + huge).issue, NegativeZero)
  assert_true(parsed("1e+" + "0".repeat(10000) + "1").value is Number(10.0))
}

///|
test "distant significant digits survive normalization around rounding midpoints" {
  let midpoint = "1.00000000000000011102230246251565404236316680908203125"
  for
    (source, bits) in [
      (midpoint + "0".repeat(70000), 0x3ff0000000000000UL),
      (midpoint + "0".repeat(70000) + "1", 0x3ff0000000000001UL),
      ("-" + midpoint + "0".repeat(70000), 0xbff0000000000000UL),
      ("-" + midpoint + "0".repeat(70000) + "1", 0xbff0000000000001UL),
    ] {
    guard parsed(source).value is Number(value) else {
      fail("expected midpoint number")
    }
    assert_eq(value.reinterpret_as_uint64(), bits)
  }
}

///|
test "negative zero and overflow are rejected including underflow to negative zero" {
  for text in ["-0", "-0.0", "-0e100", "-1e-400", "-2.4703282292062327e-324"] {
    assert_eq(rejected(text).issue, NegativeZero)
  }
  for
    text in [
      "1e400", "-1e400", "1.7976931348623159e308", "-1.7976931348623159e308",
    ] {
    assert_eq(rejected(text).issue, NumberOutOfRange)
  }
}
