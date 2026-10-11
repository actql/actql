///|
// Fixed column frames match the independently authored Python C API fixture.
// The existing Core decoder and receiver, not the Python adapter, admit values.
test "Python one-row column receipts enter the existing typed receiver losslessly" {
  let fields = decode_physical_fields(
    "[[\"id\",\"BIGINT\",null,null],[\"label\",\"VARCHAR\",null,null]]",
    transport_column_limits(),
  ).unwrap()
  let physical = prepare_physical_result(
    result_schema(),
    fields,
    result_limits(),
    100,
  ).unwrap()
  let frames = [
    "[[\"0\"],[\"e\\u0301\\u000d\\u000a😀\"]]", "[[\"1\"],[null]]", "[[\"2\"],[\"e\\u0301\\u000d\\u000a😀\"]]",
  ]
  for row, frame in frames {
    let columns = decode_transport_columns(frame, transport_column_limits()).unwrap()
    let accepted = admit_physical_chunk(physical, 1, columns).unwrap()
    assert_eq(physical_batch_rows(accepted), 1)
    let writer = @encode.writer(1024, 32, 4)
    @encode.begin_array(writer)
    for column in 0..<2 {
      @admitted.emit_wire_value(
        physical_batch_cell(accepted, 0, column).unwrap().value,
        writer,
      )
    }
    @encode.end_array(writer)
    let expected = if row == 1 {
      "[1,null]"
    } else {
      "[\{row},\"e\u0301\\r\\n😀\"]"
    }
    assert_eq(@encode.finish(writer), expected)
  }
}

///|
test "Python column receipt shape cannot waive count type or aggregate limits" {
  let fields = [("id", Integer(bits=64, signed=true)), ("label", Varchar)]
  for
    (frame, claimed_rows) in [
      ("[[\"0\"],[]]", 1),
      ("[[\"0\"],[null]]", 2),
      ("[[null],[null]]", 1),
      ("[[\"9007199254740993\"],[null]]", 1),
    ] {
    let physical = prepare_physical_result(
      result_schema(),
      fields,
      result_limits(),
      100,
    ).unwrap()
    let columns = decode_transport_columns(frame, transport_column_limits()).unwrap()
    assert_true(admit_physical_chunk(physical, claimed_rows, columns) is Err(_))
  }
  let physical = prepare_physical_result(
    result_schema(),
    fields,
    { ..result_limits(), max_rows: 1, },
    100,
  ).unwrap()
  let columns = decode_transport_columns(
    "[[\"0\"],[null]]",
    transport_column_limits(),
  ).unwrap()
  assert_true(admit_physical_chunk(physical, 1, columns) is Ok(_))
  assert_true(admit_physical_chunk(physical, 1, columns) is Err(RowLimit))
  assert_true(
    decode_transport_columns("[[0],[null]]", transport_column_limits())
    is Err(InvalidShape),
  )
}
