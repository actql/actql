///|
test "indexed assertion keys preserve authored order source and checked schema" {
  let original = row_checked(AssertRows, "{\"unique_by\":[\"amount\",\"id\"]}")
  guard @relation_typing.row_operation(original) is Some(AssertUnique(keys)) else {
    abort("unique assertion")
  }
  assert_eq(@relation_typing.assertion_key_count(original), 2)
  for index in 0..<2 {
    let key = @relation_typing.assertion_key_at(original, index).unwrap()
    assert_eq(key.field, keys[index].field)
    assert_true(physical_equal(key.source, keys[index].source))
  }
  keys.clear()
  assert_eq(@relation_typing.assertion_key_count(original), 2)
  assert_eq(
    @relation_typing.assertion_key_at(original, 0).unwrap().field,
    Unqualified("amount"),
  )
  for index in [-1, 2, 2147483647] {
    assert_true(@relation_typing.assertion_key_at(original, index) is None)
  }
  for
    other in [
      row_checked(AssertRows, "{\"where\":\"flag\"}"),
      row_checked(Sort, "[{\"id\":\"asc\"}]"),
    ] {
    assert_eq(@relation_typing.assertion_key_count(other), 0)
    assert_true(@relation_typing.assertion_key_at(other, 0) is None)
  }
}
