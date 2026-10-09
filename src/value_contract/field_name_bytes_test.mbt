///|
test "immutable field name bytes retain each constructor's original Unicode charge" {
  let name = "x".repeat(128) + "😀é"
  // 128 ASCII + four UTF-8 emoji bytes + two accent bytes, plus id=2.
  let expected = 136
  let body = "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"" +
    name +
    "\":{\"type\":\"number\",\"nullable\":false}}}"
  let decoded = author(body)
  let parameter = @value_contract.read_parameter_syntax(cursor(body), limits()).unwrap().parameter_type.contract
  let constructed = @value_contract.object_contract(
    [(name, scalar("number")), ("id", scalar("number"))],
    nullable=false,
    max_fields=2,
    max_name_bytes=expected,
  ).unwrap()
  let joined = @value_contract.join_nullability(
    constructed,
    @value_contract.with_nullability(decoded, true),
    10,
  ).unwrap()
  for
    contract in [
      decoded,
      parameter,
      constructed,
      joined,
      checked(render(decoded)),
    ] {
    guard contract.shape is @value_contract.Object(fields) else {
      fail("expected object fields")
    }
    assert_eq(@value_contract.field_name_bytes(fields), expected)
    assert_eq(@value_contract.field_at(fields, 0).unwrap().name, "id")
    assert_eq(@value_contract.field_at(fields, 1).unwrap().name, name)
  }
  assert_true(
    @value_contract.object_contract(
      [(name, scalar("number")), ("id", scalar("number"))],
      nullable=false,
      max_fields=2,
      max_name_bytes=expected - 1,
    )
    is Err(@value_contract.ConstructionLimit),
  )
  let nested_body = "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"outer\":" +
    body +
    "}}"
  for
    contract in [
      author(nested_body),
      @value_contract.read_parameter_syntax(cursor(nested_body), limits()).unwrap().parameter_type.contract,
    ] {
    guard contract.shape is @value_contract.Object(outer) &&
      @value_contract.field_at(outer, 0).unwrap().contract.shape
      is @value_contract.Object(inner) else {
      fail("expected nested object fields")
    }
    assert_eq(@value_contract.field_name_bytes(outer), 5)
    assert_eq(@value_contract.field_name_bytes(inner), expected)
  }
}
