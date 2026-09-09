///|
test "incremental key admission is exact independent and stable after rejection" {
  let keys = @decode_shape.key_admission()
  for key in ["", "a", "é", "e\u0301", "a.b", "a/b", "😀"] {
    assert_true(@decode_shape.admit_key(keys, key))
    assert_false(@decode_shape.admit_key(keys, key))
    assert_false(@decode_shape.admit_key(keys, key))
  }
  let other = @decode_shape.key_admission()
  assert_true(@decode_shape.admit_key(other, "a"))
  for index = 0; index < 10000; index = index + 1 {
    assert_true(@decode_shape.admit_key(keys, "field-" + index.to_string()))
  }
  for index = 9999; index >= 0; index = index - 1 {
    assert_false(@decode_shape.admit_key(keys, "field-" + index.to_string()))
  }
}
