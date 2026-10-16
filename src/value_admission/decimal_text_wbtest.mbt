///|
test "source decimal text normalizes exactly up to precision 38 without binary64" {
  for
    (text, precision, scale, expected) in [
      ("12.5", 12, 2, "12.50"),
      ("125e-2", 12, 2, "1.25"),
      ("1.2345678E7", 12, 2, "12345678.00"),
      ("-0.000", 38, 10, "0.0000000000"),
      ("9007199254740993.01", 38, 10, "9007199254740993.0100000000"),
      (
        "9999999999999999999999999999.9999999999", 38, 10, "9999999999999999999999999999.9999999999",
      ),
      ("-1e-10", 38, 10, "-0.0000000001"),
    ] {
    assert_eq(
      normalize_decimal_text(text, precision, scale, 1000),
      Ok(expected),
    )
  }
}

///|
test "source decimal limits and errors never round scale or overflow precision" {
  assert_eq(normalize_decimal_text("1.001", 38, 2, 100), Err(BeyondScale))
  assert_eq(normalize_decimal_text("1e28", 38, 10, 100), Err(OutOfRange))
  assert_eq(normalize_decimal_text("1e999999999", 38, 10, 100), Err(OutOfRange))
  assert_eq(
    normalize_decimal_text("1e-999999999", 38, 10, 100),
    Err(BeyondScale),
  )
  for text in ["", "+1", "01", "NaN", "1.", "1e", "1 ", "0x10"] {
    assert_eq(normalize_decimal_text(text, 38, 10, 100), Err(InvalidFormat))
  }
  assert_eq(normalize_decimal_text("123", 38, 10, 2), Err(InputLimit))
  assert_eq(normalize_decimal_text("123", 38, 10, 3), Ok("123.0000000000"))
  for
    (precision, scale, units) in [
      (0, 0, 1),
      (39, 0, 1),
      (38, -1, 1),
      (38, 39, 1),
      (38, 10, 0),
    ] {
    assert_eq(
      normalize_decimal_text("1", precision, scale, units),
      Err(InvalidLimits),
    )
  }
}

///|
test "source normalization does not relax the canonical Decimal wire admission" {
  let contract = @contract.decimal_contract(12, 2, nullable=false).unwrap()
  for text in ["12.5", "125e-1", "+12.50", "-0.00"] {
    let node = @source.parse_json_bytes(
      @utf8.encode(Json::string(text).stringify()),
      { max_input_bytes: 100, max_nodes: 2, max_depth: 2, },
    ).unwrap()
    let cursor = @decode.admit(node, {
      max_nodes: 2,
      max_depth: 2,
      max_string_bytes: 100,
      max_total_string_bytes: 100,
    }).unwrap()
    assert_true(
      admit_wire(contract, cursor, {
        max_nodes: 2,
        max_depth: 2,
        max_text_bytes: 100,
      })
      is Err(ValueIssue(InvalidDecimal, ..)),
    )
  }
}
