///|
test "private original input wire retains omission null values and original order" {
  let owner = sort_input_owner(
    @pipeline.CarrierInput(
      @carrier.relation(@carrier.typed_rows(presence_test_schema())),
    ),
    "[{\"filter\":\"id > 0\"}]",
  )
  let input = prepare_admitted_input(owner, 0, 3, stream_value_limits()).unwrap()
  let expected = ["{\"id\":3}", "{\"id\":2,\"p\":null}", "{\"id\":1,\"p\":7}"]
  for wire in expected {
    append_admitted_input_presence(
      input,
      read_retained_relation_row(
        input.buffer.schema,
        wire,
        retained_row_test_limits(),
        stream_value_limits(),
      ).unwrap(),
    ).unwrap()
  }
  let captured = finish_admitted_input(input).unwrap()
  let live = Ref(true)
  let read = prepare_supplied_relation_read(owner, 0, captured, () => live.val).unwrap()
  for row in 0..<3 {
    assert_eq(
      supplied_relation_read_row_wire(read, row, row_wire_limits()).unwrap(),
      expected[row],
    )
  }
  // Independent literal preimage, not an expected value made by the new export.
  assert_eq(
    row_wire_cid(
      supplied_relation_read_rows_identity(read, row_wire_limits()).unwrap(),
    ),
    "sha256:a0816b6c302bcb401187b6f01c5ad06f117f5d223a8aa881d7a38e7c8ee485b9",
  )
  assert_true(
    supplied_relation_read_row_wire(read, -1, row_wire_limits())
    is Err(InvalidLayout),
  )
  assert_true(
    supplied_relation_read_row_wire(read, 3, row_wire_limits())
    is Err(InvalidLayout),
  )
  assert_true(
    supplied_relation_read_row_wire(read, 2, {
      ..row_wire_limits(),
      max_bytes: 13,
    })
    is Err(Encoding(_)),
  )
  live.val = false
  assert_true(
    supplied_relation_read_row_wire(read, 0, row_wire_limits())
    is Err(InvalidLayout),
  )
  assert_true(
    supplied_relation_read_rows_identity(read, row_wire_limits())
    is Err(InvalidLayout),
  )
}
