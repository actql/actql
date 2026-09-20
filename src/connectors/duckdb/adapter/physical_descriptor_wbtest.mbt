///|
test "physical metadata is checked before empty or NULL data can hide mismatch" {
  for
    (name, expected) in [
      ("BOOLEAN", Boolean),
      ("VARCHAR", Varchar),
      ("INTEGER", Integer(bits=32, signed=true)),
      ("UBIGINT", Integer(bits=64, signed=false)),
      ("DOUBLE", Float64),
      ("DATE", Date),
      ("TIMESTAMP_TZ", TimestampTZ),
    ] {
    assert_eq(
      decode_physical_type(payload("{\"id\":\"" + name + "\"}")).unwrap(),
      expected,
    )
  }
  assert_eq(
    decode_physical_type(
      payload("{\"id\":\"DECIMAL\",\"precision\":38,\"scale\":18}"),
    ).unwrap(),
    Decimal(precision=38, scale=18),
  )
  for name in ["TIMESTAMP", "TIMESTAMP_S", "TIMESTAMP_MS", "TIMESTAMP_NS"] {
    let physical = decode_physical_type(payload("{\"id\":\"" + name + "\"}")).unwrap()
    assert_eq(physical, NaiveTimestamp)
    assert_true(
      prepare_value_mapping(
        physical,
        @contract.primitive(@contract.TimestampType, nullable=true),
      )
      is Err(ImplicitTimezone),
    )
  }
  for
    descriptor in [
      "{\"id\":\"DECIMAL\",\"precision\":39,\"scale\":0}", "{\"id\":\"DECIMAL\",\"precision\":4,\"scale\":5}",
      "{\"id\":\"DECIMAL\",\"precision\":4}", "{\"id\":\"INTEGER\",\"alias\":\"number\"}",
      "{\"id\":\"VARCHAR\",\"scale\":0}", "{\"id\":\"LIST\"}", "{}", "null",
    ] {
    assert_true(decode_physical_type(payload(descriptor)) is Err(_))
  }
}

///|
test "physical field metadata has one bounded Connector decoder" {
  let limits : TransportColumnLimits = {
    max_bytes: 512,
    max_nodes: 32,
    max_columns: 4,
    max_rows: 4,
    max_text_bytes: 128,
  }
  assert_eq(
    decode_physical_fields(
      "[[\"id\",\"INTEGER\",null,null]," +
      "[\"amount\",\"DECIMAL\",\"38\",\"18\"]]",
      limits,
    ).unwrap(),
    [
      ("id", Integer(bits=32, signed=true)),
      ("amount", Decimal(precision=38, scale=18)),
    ],
  )
  assert_true(
    decode_physical_fields("[[\"id\",\"INTEGER\",null]]", limits)
    is Err(InvalidFields),
  )
  assert_true(
    decode_physical_fields("[[\"id\",\"LIST\",null,null]]", limits)
    is Err(Descriptor(UnsupportedType)),
  )
  assert_true(
    decode_physical_fields(
      "[[\"a\",\"INTEGER\",null,null]," + "[\"b\",\"INTEGER\",null,null]]",
      { ..limits, max_columns: 1, },
    )
    is Err(Transport(ColumnLimit)),
  )
}
