///|
test "measurement metadata follows the original schema width and qualified spelling constructor" {
  let contract = @contract.primitive(@contract.StringType, nullable=true)
  let wide = @schema.from_fields(
    Array::makei(102, index => (@schema.Unqualified("field_\{index}"), contract)),
    max_fields=102,
    max_name_bytes=2048,
  ).unwrap()
  // Shared representation units: (n+8)headers, (5n+16)refs, (n+16)words.
  assert_eq(row_measurement_workspace(wide), Some(6912L))
  let small = @schema.from_fields(
    [("a", contract), ("b", contract), ("c", contract)].map(pair => {
      (@schema.Unqualified(pair.0), pair.1)
    }),
    max_fields=3,
    max_name_bytes=32,
  ).unwrap()
  assert_eq(row_measurement_workspace(small), Some(576L))
  let qualified = @schema.from_fields(
    [(@schema.Qualified(@schema.Left, "é"), contract)],
    max_fields=1,
    max_name_bytes=32,
  ).unwrap()
  // One original qualified name adds one header and six UTF16 units.
  assert_eq(row_measurement_workspace(qualified), Some(476L))
}

///|
test "selected measurement width does not waive explicit column or ordering work limits" {
  let names = Array::makei(102, index => "field_\{index}")
  assert_true(
    @execution.prepare_row_wire_order(names, 101, 100000) is Err(OrderLimit),
  )
  assert_true(
    @execution.prepare_row_wire_order(names, 102, 101) is Err(OrderLimit),
  )
  assert_true(@execution.prepare_row_wire_order(names, 102, 100000) is Ok(_))
}
