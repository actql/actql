///|
test "original ParameterSyntax retains @value_contract.Decimal precision during its sole typed construction" {
  let root = cursor(
    "{\"type\":\"object\",\"fields\":{\"a\":{\"type\":\"array\",\"items\":{\"type\":\"decimal\",\"precision\":4,\"scale\":2}},\"b\":{\"type\":\"decimal\",\"precision\":8,\"scale\":0}},\"default\":{\"a\":[\"1.20\"],\"b\":\"12\"},\"meta\":{\"type\":\"decimal\",\"precision\":999}}",
  )
  let original = @value_contract.read_parameter_syntax(root, limits()).unwrap()
  assert_eq(
    @value_contract.parameter_syntax_maximum_decimal_precision(original),
    8,
  )
  assert_true(physical_equal(original.parameter_type, original.parameter_type))
  assert_true(original.default_value is Some(_) && original.metadata is Some(_))
  let declaration = original.parameter_type
  guard declaration.rule is @value_contract.Properties(fields) else {
    fail("original fields")
  }
  guard @value_contract.parameter_field_at(fields, 0).unwrap().1.rule
    is @value_contract.Items(item, ..) else {
    fail("original items")
  }
  guard item.contract.shape is @value_contract.Decimal(precision~, scale~) else {
    fail("original @value_contract.Decimal")
  }
  assert_eq((precision, scale), (4, 2))
  assert_eq(
    @value_contract.parameter_syntax_maximum_decimal_precision(original),
    8,
  )
}

///|
test "retained @value_contract.Decimal quantity ignores names enum data and default meta syntax lookalikes" {
  let original = @value_contract.read_parameter_syntax(
    cursor(
      "{\"type\":\"string\",\"enum\":[\"decimal\"],\"default\":\"decimal\",\"meta\":{\"type\":\"decimal\",\"precision\":38}}",
    ),
    limits(),
  ).unwrap()
  assert_eq(
    @value_contract.parameter_syntax_maximum_decimal_precision(original),
    0,
  )
  assert_true(
    @value_contract.read_parameter_syntax(
      cursor("{\"type\":\"decimal\",\"precision\":39,\"scale\":0}"),
      limits(),
    )
    is Err(@value_contract.ContractIssue(@value_contract.InvalidRange, ..)),
  )
  assert_true(
    @value_contract.read_parameter_syntax(
      cursor("{\"type\":\"decimal\",\"precision\":4,\"scale\":5}"),
      limits(),
    )
    is Err(@value_contract.ContractIssue(@value_contract.InvalidRange, ..)),
  )
}
