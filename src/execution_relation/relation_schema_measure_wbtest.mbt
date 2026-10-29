///|
fn compiler_measure_schema() -> @schema.Schema {
  let number = @contract.primitive(NumberType, nullable=false)
  let array = @contract.array_contract(
    number,
    nullable=true,
    max_items=Some(3L),
  ).unwrap()
  @schema.from_presence_fields(
    [
      (@schema.Unqualified("é/😀"), array, @schema.Conditional),
      (@schema.Unqualified("id"), number, @schema.Required),
    ],
    max_fields=2,
    max_name_bytes=32,
  ).unwrap()
}

///|
test "schema construction measurement uses the exact Unicode conditional contract codec" {
  let schema = compiler_measure_schema()
  let expected =
    #|{"id":{"nullable":false,"type":"number"},"é/😀":{"contract":{"items":{"nullable":false,"type":"number"},"max_items":3,"nullable":true,"type":"array"},"presence":"conditional"}}
  let bytes = @utf8.encode(expected).length()
  let limits = { max_fields: 2, max_bytes: bytes, max_nodes: 13, max_depth: 4, }
  assert_eq(
    measure_relation_schema_identity(schema, limits).unwrap(),
    (bytes, 13, 4),
  )
  let original = identify_relation_schema(schema, limits).unwrap()
  assert_eq(relation_schema_wire(original), expected)
  assert_eq(relation_schema_usage(original), (bytes, 13, 2))
  assert_eq(relation_schema_field_names(original), ["id", "é/😀"])
  for
    short in [
      { ..limits, max_bytes: bytes - 1, },
      { ..limits, max_nodes: 12, },
      { ..limits, max_depth: 3, },
    ] {
    assert_true(
      measure_relation_schema_identity(schema, short)
      is Err(Encoding(@encode.OutputLimit)),
    )
    assert_true(
      identify_relation_schema(schema, short)
      is Err(Encoding(@encode.OutputLimit)),
    )
  }
  assert_true(
    measure_relation_schema_identity(schema, { ..limits, max_fields: 1, })
    is Err(FieldLimit),
  )
  assert_true(
    measure_relation_schema_identity(schema, { ..limits, max_nodes: 0, })
    is Err(InvalidLimits),
  )
}

///|
test "schema measurement continuation creates no wire identity and retires the original input" {
  let value = start_relation_schema_output(
    compiler_measure_schema(),
    schema_identity_limits(),
    true,
  ).unwrap()
  assert_true(
    value.measurement_only &&
    value.wire_writer is None &&
    value.identity is None,
  )
  while true {
    let (done, used) = advance_relation_schema_identity(value, 1).unwrap()
    assert_true(used == 1)
    if done {
      break
    }
  }
  assert_true(
    value.measured is Some(_) &&
    value.identity is None &&
    value.names.is_empty(),
  )
  assert_true(finish_relation_schema_identity(value) is Err(NotFinished))
  assert_true(cancel_relation_schema_identity(value))
  assert_true(
    value.measured is None &&
    value.schema is None &&
    value.hash_writer is None &&
    value.wire_writer is None,
  )
  assert_false(cancel_relation_schema_identity(value))
  assert_true(advance_relation_schema_identity(value, 1) is Err(Closed))
}

///|
test "schema measurement cancellation clears an in-flight original field continuation" {
  let number = @contract.primitive(NumberType, nullable=false)
  let schema = @schema.from_fields(
    [(@schema.Unqualified("name".repeat(256)), number)],
    max_fields=1,
    max_name_bytes=2048,
  ).unwrap()
  let value = start_relation_schema_output(
    schema,
    { max_fields: 1, max_bytes: 2000, max_nodes: 10, max_depth: 10, },
    true,
  ).unwrap()
  while value.key is None {
    advance_relation_schema_identity(value, 1).unwrap() |> ignore
  }
  assert_true(value.identity is None && value.measured is None)
  assert_true(cancel_relation_schema_identity(value))
  assert_true(
    value.key is None &&
    value.contract is None &&
    value.schema is None &&
    value.hash_writer is None &&
    value.wire_writer is None,
  )
  assert_true(advance_relation_schema_identity(value, 1) is Err(Closed))
}
