///|
fn parameter_text(value : @admitted.CheckedValue) -> String raise {
  let parameter = prepare_physical_parameter(value).unwrap()
  let output = @encode.writer(1000, 20, 4)
  emit_physical_parameter(parameter, output)
  @encode.finish(output)
}

///|
test "prepared parameters preserve exact scalar physical content" {
  for
    (kind, input, expected) in [
      (
        @contract.BooleanType,
        "true",
        "{\"type\":{\"id\":\"BOOLEAN\"},\"value\":true}",
      ),
      (
        @contract.StringType,
        "\"日本語\"",
        "{\"type\":{\"id\":\"VARCHAR\"},\"value\":\"日本語\"}",
      ),
      (
        @contract.NumberType,
        "1",
        "{\"type\":{\"id\":\"DOUBLE\"},\"value\":\"3ff0000000000000\"}",
      ),
      (
        @contract.NumberType,
        "null",
        "{\"type\":{\"id\":\"DOUBLE\"},\"value\":null}",
      ),
      (
        @contract.DateType,
        "\"2000-02-29\"",
        "{\"type\":{\"id\":\"DATE\"},\"value\":\"11016\"}",
      ),
      (
        @contract.TimestampType,
        "\"1969-12-31T23:59:59.999Z\"",
        "{\"type\":{\"id\":\"TIMESTAMP_TZ\"},\"value\":\"-1000\"}",
      ),
    ] {
    let checked = @admitted.admit(
      @contract.primitive(kind, nullable=true),
      payload(input),
      { max_nodes: 1, max_depth: 0, max_text_bytes: 1000, },
    ).unwrap()
    assert_eq(parameter_text(checked), expected)
  }
  let decimal = value(
    prepare_value_mapping(
      Decimal(precision=38, scale=18),
      @contract.decimal_contract(38, 18, nullable=false).unwrap(),
    ).unwrap(),
    "\"99999999999999999999999999999999999999\"",
  ).unwrap()
  assert_eq(
    parameter_text(decimal),
    "{\"type\":{\"id\":\"DECIMAL\",\"precision\":38,\"scale\":18},\"value\":\"99999999999999999999999999999999999999\"}",
  )
}

///|
test "epoch conversion roundtrips admitted Gregorian boundary dates" {
  for days in [-719528, -719469, -719468, -25509, -1, 0, 11016, 2932896] {
    assert_eq(admitted_date_days(date_text(days).unwrap()), days)
  }
  for
    micros in [
      -62167219200000000L, -1000L, 0L, 1789302896123000L, 253402300799999000L,
    ] {
    assert_eq(
      admitted_timestamp_micros(timestamp_text(micros).unwrap()),
      micros,
    )
  }
}
