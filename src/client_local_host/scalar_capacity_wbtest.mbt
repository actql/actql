///|
fn client_local_scalar_node_limit(width : Int, max_rows : Int) -> Int? {
  if width < 1 {
    return None
  }
  client_local_scalar_product(width.to_int64(), max_rows, 3)
}

///|
test "scalar capacity retains nullable scalar fields and falls back for text" {
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("n"), @contract.primitive(NumberType, nullable=true)),
      (
        @schema.Unqualified("b"),
        @contract.primitive(BooleanType, nullable=true),
      ),
    ],
    max_fields=100,
    max_name_bytes=100,
  ).unwrap()
  assert_eq(client_local_scalar_schema_width(schema), Some(2))
  let text = @schema.from_fields(
    [
      (
        @schema.Unqualified("s"),
        @contract.primitive(StringType, nullable=false),
      ),
    ],
    max_fields=100,
    max_name_bytes=100,
  ).unwrap()
  assert_eq(client_local_scalar_schema_width(text), None)
  let nested = @schema.from_fields(
    [
      (
        @schema.Unqualified("a"),
        @contract.array_contract(
          @contract.primitive(NumberType, nullable=false),
          nullable=false,
        ).unwrap(),
      ),
    ],
    max_fields=100,
    max_name_bytes=100,
  ).unwrap()
  assert_eq(client_local_scalar_schema_width(nested), None)
}

///|
test "scalar capacity cannot replace absent evidence or the retained ceiling" {
  assert_eq(client_local_scalar_nodes([], 100), None)
  assert_eq(client_local_scalar_nodes([], 0), None)
  let (values, execution, measurement) = client_local_execution_limits(
    scalar_sequences=Some([]),
  )
  assert_eq(values.max_nodes, 20000)
  assert_eq(values.max_text_bytes, 500000)
  assert_eq(execution.rows.max_rows, 100)
  assert_eq(measurement.max_nodes, 20000)
  assert_eq(measurement.max_bytes, 500000)
  assert_eq(
    client_local_store_inventory([1], 536870912L, 1L, 0L, 536870912L),
    None,
  )
}

///|
test "scalar capacity node product derives finite demand without representation overflow" {
  assert_eq(client_local_scalar_node_limit(2, 100), Some(200))
  assert_eq(client_local_scalar_node_limit(100, 200), Some(20000))
  assert_eq(client_local_scalar_node_limit(100, 201), Some(20100))
  assert_eq(client_local_scalar_node_limit(1, 20000), Some(20000))
  assert_eq(client_local_scalar_node_limit(1, 20001), Some(20001))
  assert_eq(client_local_scalar_node_limit(2147483647, 2147483647), None)
  assert_eq(client_local_scalar_node_limit(1, 0), None)
  assert_eq(client_local_scalar_node_limit(0, 100), None)
}
