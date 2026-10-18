///|
fn signed64_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 1000, max_nodes: 100, max_depth: 8, },
      source_path="signed64.json",
    ).unwrap(),
    {
      max_nodes: 100,
      max_depth: 8,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
fn signed64_checked(text : String) -> CheckedValue {
  admit(
    @contract.primitive(@contract.Signed64Type, nullable=false),
    signed64_cursor("\"" + text + "\""),
    { max_nodes: 1, max_depth: 0, max_text_bytes: text.length(), },
  ).unwrap()
}

///|
test "signed64 admits the entire exact domain with original Contract and input budget" {
  let contract = @contract.primitive(@contract.Signed64Type, nullable=false)
  for
    text in [
      "-9223372036854775808", "-9007199254740993", "-1", "0", "1", "9007199254740992",
      "9007199254740993", "9223372036854775807",
    ] {
    let cursor = signed64_cursor("\"" + text + "\"")
    let (checked, nodes, bytes) = admit_usage(contract, cursor, {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: text.length(),
    }).unwrap()
    assert_true(physical_equal(checked.contract, contract))
    guard! checked.value is Signed64(value)
    assert_eq(value.to_string(), text)
    assert_eq((nodes, bytes), (1, text.length()))
    assert_true(
      admit(contract, cursor, {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: text.length() - 1,
      })
      is Err(_),
    )
  }
}

///|
test "signed64 refuses noncanonical strings and both overflow neighbors without coercion" {
  let contract = @contract.primitive(@contract.Signed64Type, nullable=false)
  for
    text in [
      "", "-0", "+1", "01", "-01", " 1", "1 ", "1.0", "1e0", "−1", "9223372036854775808",
      "-9223372036854775809", "100000000000000000000",
    ] {
    assert_true(
      admit(contract, signed64_cursor("\"" + text + "\""), {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 100,
      })
      is Err(ValueIssue(InvalidSigned64, ..)),
    )
  }
  for text in ["0", "9007199254740993", "true", "null", "[]", "{}"] {
    assert_true(
      admit(contract, signed64_cursor(text), {
        max_nodes: 10,
        max_depth: 2,
        max_text_bytes: 100,
      })
      is Err(_),
    )
  }
}

///|
test "signed64 runtime recheck preserves original type and never upgrades JSON Number or Decimal" {
  let contract = @contract.primitive(@contract.Signed64Type, nullable=false)
  let limits : Limits = { max_nodes: 1, max_depth: 0, max_text_bytes: 0, }
  let value = signed64_value(-9223372036854775808L)
  let checked = recheck_runtime_value(value, contract, limits).unwrap()
  assert_true(physical_equal(checked.contract, contract))
  assert_true(checked.value is Signed64(-9223372036854775808L))
  for
    other in [
      @contract.primitive(@contract.NumberType, nullable=false),
      @contract.decimal_contract(19, 0, nullable=false).unwrap(),
      @contract.primitive(@contract.StringType, nullable=false),
      @contract.primitive(@contract.JsonType, nullable=false),
    ] {
    assert_true(
      recheck_runtime_value(value, other, {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 100,
      })
      is None,
    )
  }
  for
    foreign in [
      number_value(1.0).unwrap(),
      text_value("1", 1).unwrap(),
      decimal_from_coefficient("1", 19, 0).unwrap(),
    ] {
    assert_true(
      recheck_runtime_value(foreign, contract, {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 100,
      })
      is None,
    )
  }
  assert_true(
    recheck_runtime_value(value, contract, { ..limits, max_nodes: 0, }) is None,
  )
  assert_true(recheck_runtime_value(Null, contract, limits) is None)
  let nullable = @contract.primitive(@contract.Signed64Type, nullable=true)
  assert_true(recheck_runtime_value(Null, nullable, limits) is Some(_))
  assert_true(
    canonical_scalar_text(checked, 100) is None,
    msg="the existing to_string signature is not widened by value admission",
  )
}

///|
test "signed64 wire is an exact bounded String and typed identity has its own tag" {
  for
    text in ["-9223372036854775808", "9007199254740993", "9223372036854775807"] {
    let checked = signed64_checked(text)
    let wire = "\"" + text + "\""
    let output = @encode.writer(wire.length(), 1, 0)
    emit_checked_wire_value(checked, output)
    assert_eq(@encode.finish(output), wire)
    let measured = @encode.measuring_writer(wire.length(), 1, 0)
    emit_checked_wire_value(checked, measured)
    assert_eq(@encode.finish_measurement_usage(measured), (wire.length(), 1, 0))
    let short = @encode.writer(wire.length() - 1, 1, 0)
    assert_true(
      try {
        emit_checked_wire_value(checked, short)
        false
      } catch {
        _ => true
      },
    )
    assert_eq(
      complete_order_key(checked, {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 0,
      }).unwrap(),
      "[\"int64\",\"" + text + "\"]",
    )
  }
}

///|
test "signed64 equality and semantic key order distinguish integers beyond binary64" {
  let texts = [
    "-9223372036854775808", "-9007199254740993", "-1", "0", "1", "9007199254740992",
    "9007199254740993", "9223372036854775807",
  ]
  for index in (0..<texts.length()) - 1 {
    let left = signed64_checked(texts[index])
    let right = signed64_checked(texts[index + 1])
    assert_eq(compare_key_values(left, right), Ok(-1))
    assert_eq(compare_author_order_values(right, left), Ok(1))
    let bounded = start_bounded_key_comparison(left, right).unwrap()
    assert_true(
      advance_bounded_key_comparison(bounded, 1)
      is Ok(KeyComparisonComplete(order=-1, work=1)),
    )
    assert_true(
      @canonical.compare_utf16(
        typed_key_order_text(left).unwrap(),
        typed_key_order_text(right).unwrap(),
      ) <
      0,
    )
    let equal = start_complete_equality(left, right, {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: 0,
    }).unwrap()
    assert_true(
      advance_complete_equality(equal, 1)
      is EqualityComplete(equal=false, work=1),
    )
  }
  let value = signed64_checked("0")
  assert_eq(
    typed_key_order_text(signed64_checked("-9223372036854775808")).unwrap(),
    "0000000000000000",
  )
  assert_eq(typed_key_order_text(value).unwrap(), "8000000000000000")
  assert_eq(
    typed_key_order_text(signed64_checked("9223372036854775807")).unwrap(),
    "ffffffffffffffff",
  )
  let number : CheckedValue = {
    contract: @contract.primitive(@contract.NumberType, nullable=false),
    value: Number(0.0),
  }
  assert_eq(compare_key_values(value, number), Err(InvalidKey))
}

///|
test "signed64 canonical conversion requires its original checked schema" {
  let contract = @contract.primitive(@contract.Signed64Type, nullable=false)
  let canonical = @identity.from_json(
    Json::string("9007199254740993"),
    1,
    0,
    16,
  )
  let limits : Limits = { max_nodes: 1, max_depth: 0, max_text_bytes: 16, }
  let conversion = start_canonical_conversion(
    canonical,
    limits,
    contract=Some(contract),
    wire=true,
  ).unwrap()
  assert_true(
    advance_canonical_conversion(conversion) is CanonicalConversionContinue,
  )
  guard! advance_canonical_conversion(conversion)
    is CanonicalConversionComplete(value)
  assert_true(value is Signed64(9007199254740993L))
  let untyped = start_canonical_conversion(canonical, limits).unwrap()
  assert_true(
    advance_canonical_conversion(untyped) is CanonicalConversionContinue,
  )
  guard! advance_canonical_conversion(untyped)
    is CanonicalConversionComplete(text)
  assert_true(text is Text("9007199254740993"))
}
