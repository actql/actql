///|
fn payload(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 1000,
      max_nodes: 10,
      max_depth: 3,
    }).unwrap(),
    {
      max_nodes: 10,
      max_depth: 3,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
fn mapping(physical : PhysicalType, kind : @contract.Primitive) -> ValueMapping {
  prepare_value_mapping(physical, @contract.primitive(kind, nullable=true)).unwrap()
}

///|
fn value(
  map : ValueMapping,
  text : String,
) -> Result[@admitted.CheckedValue, ValueIssue] {
  admit_physical_value(map, payload(text), {
    max_nodes: 1,
    max_depth: 0,
    max_text_bytes: 1000,
  })
}

///|
test "integer transport rejects loss, not an artificial safe integer ceiling" {
  let map = mapping(Integer(bits=64, signed=true), @contract.NumberType)
  assert_true(
    value(map, "\"9007199254740992\"").unwrap().value
    is @admitted.Number(9007199254740992.0),
  )
  assert_true(value(map, "\"9007199254740993\"") is Err(LossyInteger))
  assert_true(
    value(map, "\"-9223372036854775808\"").unwrap().value
    is @admitted.Number(-9223372036854775808.0),
  )
  assert_true(value(map, "\"9223372036854775807\"") is Err(LossyInteger))
  assert_true(value(map, "\"9223372036854775808\"") is Err(OutOfRange))
  let huge = mapping(Integer(bits=128, signed=false), @contract.NumberType)
  assert_true(
    value(huge, "\"18446744073709551616\"").unwrap().value
    is @admitted.Number(18446744073709551616.0),
  )
  assert_true(value(huge, "\"18446744073709551617\"") is Err(LossyInteger))
  for text in ["\"01\"", "\"-0\"", "\"+1\"", "\"1.0\"", "\"\""] {
    assert_true(value(map, text) is Err(InvalidPhysicalValue))
  }
}

///|
test "decimal coefficients stay exact at precision 38 and scale boundaries" {
  let contract = @contract.decimal_contract(38, 2, nullable=true).unwrap()
  let map = prepare_value_mapping(Decimal(precision=38, scale=2), contract).unwrap()
  let maximum = value(map, "\"99999999999999999999999999999999999999\"").unwrap()
  guard maximum.value is @admitted.Decimal(d) else { fail("decimal expected") }
  assert_eq(d.coefficient, "99999999999999999999999999999999999999")
  assert_eq(d.scale, 2)
  assert_eq(decimal_text("-1", 2), "-0.01")
  assert_eq(decimal_text("0", 2), "0.00")
  assert_eq(decimal_text("0", 0), "0")
  assert_eq(decimal_text("1", 38), "0.00000000000000000000000000000000000001")
  assert_true(
    value(map, "\"100000000000000000000000000000000000000\"") is Err(OutOfRange),
  )
  assert_true(
    prepare_value_mapping(Decimal(precision=38, scale=3), contract)
    is Err(TypeMismatch),
  )
}

///|
test "timestamps reject lost precision and implicit timezone; dates preserve Gregorian boundaries" {
  let map = mapping(TimestampTZ, @contract.TimestampType)
  assert_true(
    value(map, "\"1789302896123000\"").unwrap().value
    is @admitted.Timestamp("2026-09-13T12:34:56.123Z"),
  )
  assert_true(value(map, "\"1789302896123456\"") is Err(LossyTimestamp))
  assert_true(
    value(map, "\"-1000\"").unwrap().value
    is @admitted.Timestamp("1969-12-31T23:59:59.999Z"),
  )
  assert_true(
    value(map, "\"-62167219200000000\"").unwrap().value
    is @admitted.Timestamp("0000-01-01T00:00:00.000Z"),
  )
  assert_true(
    value(map, "\"253402300799999000\"").unwrap().value
    is @admitted.Timestamp("9999-12-31T23:59:59.999Z"),
  )
  assert_true(value(map, "\"253402300800000000\"") is Err(OutOfRange))
  assert_true(
    prepare_value_mapping(
      NaiveTimestamp,
      @contract.primitive(@contract.TimestampType, nullable=true),
    )
    is Err(ImplicitTimezone),
  )
  let date = mapping(Date, @contract.DateType)
  for
    (days, expected) in [
      ("\"0\"", "1970-01-01"),
      ("\"11016\"", "2000-02-29"),
      ("\"-719528\"", "0000-01-01"),
      ("\"2932896\"", "9999-12-31"),
    ] {
    guard value(date, days).unwrap().value is @admitted.Date(actual) else {
      fail("date expected")
    }
    assert_eq(actual, expected)
  }
  assert_true(value(date, "\"2147483647\"") is Err(OutOfRange))
}

///|
test "floating transport, NULL, text and budgets still use shared admission" {
  let number = mapping(Float64, @contract.NumberType)
  assert_true(
    value(number, "\"3ff0000000000000\"").unwrap().value
    is @admitted.Number(1.0),
  )
  assert_true(value(number, "\"7ff0000000000000\"") is Err(_))
  assert_true(value(number, "null").unwrap().value is @admitted.Null)
  let text = mapping(Varchar, @contract.StringType)
  assert_true(
    value(text, "\"日本語\"").unwrap().value is @admitted.Text("日本語"),
  )
  // Physical transport and source admission both preserve decoded String values.
  for received in ["e\u0301", "a\r\nb"] {
    let raw = @decode.admit(
      {
        value: @source.String(received),
        span: @decode.cursor_span(payload("null")),
      },
      {
        max_nodes: 1,
        max_depth: 0,
        max_string_bytes: 1000,
        max_total_string_bytes: 1000,
      },
    ).unwrap()
    assert_true(
      admit_physical_value(text, raw, {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 1000,
      }).unwrap().value
      is @admitted.Text(actual) &&
      actual == received,
    )
  }
  assert_true(
    admit_physical_value(number, payload("\"3ff0000000000000\""), {
      max_nodes: 0,
      max_depth: 0,
      max_text_bytes: 1000,
    })
    is Err(Admission(@admitted.ValueIssue(@admitted.BudgetExceeded, ..))),
  )
  assert_true(
    prepare_value_mapping(
      Varchar,
      @contract.primitive(@contract.NumberType, nullable=true),
    )
    is Err(TypeMismatch),
  )
}
