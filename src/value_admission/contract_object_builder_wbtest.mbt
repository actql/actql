///|
test "contract object builder fixes canonical names and exact append order" {
  let name = "x".repeat(256)
  let contract = typed_steps_contract(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"" +
    name +
    "b\":{\"type\":\"number\",\"nullable\":true},\"" +
    name +
    "a\":{\"type\":\"number\",\"nullable\":true}}}",
  )
  let builder = prepare_contract_object_value(contract).unwrap()
  assert_false(append_contract_object_field(builder, 1, null_value()))
  assert_false(append_object_field(builder, "foreign", null_value()))
  assert_true(
    append_contract_object_field(builder, 0, number_value(7).unwrap()),
  )
  assert_false(append_contract_object_field(builder, 0, null_value()))
  assert_true(finish_object_value(builder) is None)
  assert_true(append_contract_object_field(builder, 1, null_value()))
  assert_false(append_contract_object_field(builder, 2, null_value()))
  guard finish_object_value(builder) is Some(Object(fields)) else {
    abort("contract object")
  }
  assert_eq(element_at(fields, 0).map(entry => entry.0), Some(name + "a"))
  assert_true(element_at(fields, 0) is Some((_, Number(7))))
  assert_eq(element_at(fields, 1).map(entry => entry.0), Some(name + "b"))
  assert_true(element_at(fields, 1) is Some((_, Null)))
  assert_false(append_contract_object_field(builder, 1, null_value()))
  assert_true(finish_object_value(builder) is None)
  let cancelled = prepare_contract_object_value(contract).unwrap()
  assert_true(append_contract_object_field(cancelled, 0, null_value()))
  assert_true(cancel_object_value(cancelled))
  assert_false(cancel_object_value(cancelled))
  assert_false(append_contract_object_field(cancelled, 1, null_value()))
  assert_true(finish_object_value(cancelled) is None)
  assert_true(
    prepare_contract_object_value(
      @contract.primitive(@contract.NumberType, nullable=false),
    )
    is None,
  )
  let unbound = prepare_object_value(1).unwrap()
  assert_false(append_contract_object_field(unbound, 0, null_value()))
}
