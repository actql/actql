///|
fn retained_row_test_limits() -> RetainedRowDecodeLimits {
  { max_bytes: 4096, max_nodes: 100, max_depth: 10, max_text_bytes: 4096, }
}

///|
test "retained wire rows convert with exact owner and canonical identity" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let conversion = prepare_completed_output_import(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
    append_completed_output_import_wire(
      conversion,
      row,
      retained_row_test_limits(),
    ).unwrap()
  }
  let result = finish_completed_output_import(conversion).unwrap()
  assert_true(completed_has_cell_access(result))
  assert_eq(
    row_wire_cid(identify_completed_rows(result, row_wire_limits()).unwrap()),
    row_wire_cid(identify_completed_rows(source, row_wire_limits()).unwrap()),
  )
  assert_true(completed_output_matches_port(result, owner, Step(1)))
}

///|
test "wire decode preserves typed scalars nested values and number extremes" {
  let number = @contract.primitive(NumberType, nullable=false)
  let cases : Array[(@contract.Contract, String)] = [
    (@contract.with_nullability(number, true), "null"),
    (@contract.primitive(BooleanType, nullable=false), "true"),
    (@contract.primitive(StringType, nullable=false), "\"é😀\""),
    (@contract.primitive(DateType, nullable=false), "\"2026-09-16\""),
    (
      @contract.primitive(TimestampType, nullable=false),
      "\"2026-09-16T00:00:00.000Z\"",
    ),
    (
      @contract.decimal_contract(38, 2, nullable=false).unwrap(),
      "\"123456789012345678901234567890123456.78\"",
    ),
    (@contract.array_contract(number, nullable=false).unwrap(), "[1,2]"),
    (@contract.vector_contract(2, nullable=false).unwrap(), "[1,2]"),
    (
      @contract.primitive(JsonType, nullable=false),
      "{\"a\":[null,{\"b\":true}]}",
    ),
    (number, "5e-324"),
    (number, "1.7976931348623157e+308"),
  ]
  for (contract, wire) in cases {
    let schema = @schema.from_fields(
      [(Unqualified("x"), contract)],
      max_fields=1,
      max_name_bytes=1,
    ).unwrap()
    let decoded = decode_retained_row(
      schema,
      "{\"x\":" + wire + "}",
      retained_row_test_limits(),
    )
    assert_true(decoded is Ok(_), msg="failed wire: " + wire)
    let row = decoded.unwrap()
    assert_true(physical_equal(row[0].contract, contract))
    let writer = @encode.writer(4096, 100, 10)
    @admitted.emit_wire_value(row[0].value, writer)
    assert_eq(@encode.finish(writer), wire)
  }
}

///|
test "wire conversion does not normalize invalid text or accept shape and parse overflows" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  for
    text in [
      "{\"n\":1,\"s\":\"e\\u0301\"}", "{\"n\":1,\"s\":\"a\\r\\nb\"}", "{\"n\":-0,\"s\":\"é\"}",
      "{\"n\":1}", "{\"n\":1,\"s\":\"é\",\"extra\":0}", "{\"n\":1,\"s\":}", "[[[[[]]]]]",
    ] {
    let conversion = prepare_completed_output_import(
      source,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    assert_true(
      append_completed_output_import_wire(
        conversion,
        text,
        retained_row_test_limits(),
      )
      is Err(_),
    )
    assert_true(finish_completed_output_import(conversion) is Err(Closed))
  }
  for
    limits in [
      { ..retained_row_test_limits(), max_nodes: 1, },
      { ..retained_row_test_limits(), max_bytes: 2, },
      { ..retained_row_test_limits(), max_text_bytes: 1, },
      { ..retained_row_test_limits(), max_depth: 0, },
    ] {
    let conversion = prepare_completed_output_import(
      source,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    assert_true(
      append_completed_output_import_wire(
        conversion, "{\"n\":1,\"s\":\"é\"}", limits,
      )
      is Err(_),
    )
  }
}
