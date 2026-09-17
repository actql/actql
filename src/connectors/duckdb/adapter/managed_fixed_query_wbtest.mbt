///|
fn managed_limit_schema(width : Int) -> @schema.Schema {
  @schema.from_fields(
    Array::makei(width, i => {
      (
        @schema.Unqualified("c" + i.to_string()),
        @contract.primitive(@contract.NumberType, nullable=false),
      )
    }),
    max_fields=width,
    max_name_bytes=1000,
  ).unwrap()
}

///|
test "managed create schema admits the exact column limit" {
  assert_true(
    compile_managed_fixed_create_schema(
      managed_limit_schema(10),
      "input",
      10,
      10000,
    )
    is Ok(_),
  )
  assert_true(
    compile_managed_fixed_create_schema(
      managed_limit_schema(11),
      "input",
      10,
      10000,
    )
    is Err(Limit),
  )
  assert_true(
    compile_managed_fixed_create_schema(
      managed_limit_schema(0),
      "input",
      10,
      10000,
    )
    is Err(UnsupportedShape),
  )
  for (columns, bytes) in [(-1, 10000), (10, -1)] {
    assert_true(
      compile_managed_fixed_create_schema(
        managed_limit_schema(1),
        "input",
        columns,
        bytes,
      )
      is Err(InvalidLimits),
    )
  }
}
