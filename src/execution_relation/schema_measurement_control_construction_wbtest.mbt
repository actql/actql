///|
test "measurement controls are independent of schema width and never own identity names" {
  let number = @contract.primitive(NumberType, nullable=false)
  let fields = Array::makei(129, index => {
    (
      @schema.Qualified(Left, "k" + (1000 + index).to_string()),
      number,
      @schema.Conditional,
    )
  })
  let wide = @schema.from_presence_fields(
    fields,
    max_fields=129,
    max_name_bytes=10000,
  ).unwrap()
  let empty = @schema.from_presence_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let controls = relation_schema_measurement_control_extent()
  assert_eq(controls.max_record_references, 8)
  assert_eq(controls.max_record_words, 11)
  assert_eq(controls.reference_array_slots, 12L)
  assert_eq(controls.collections.record_headers, 42L)
  for schema in [empty, wide] {
    let value = start_relation_schema_output(
      schema,
      { max_fields: 129, max_bytes: 100000, max_nodes: 10000, max_depth: 20, },
      true,
    ).unwrap()
    assert_true(value.measurement_only && value.wire_writer is None)
    while true {
      let (done, _) = advance_relation_schema_identity(value, 1).unwrap()
      assert_true(value.names.is_empty() && value.identity is None)
      if done {
        break
      }
    }
    assert_true(value.measured is Some(_))
    assert_true(cancel_relation_schema_identity(value))
    assert_true(value.closed && value.names.is_empty() && value.schema is None)
  }
}
