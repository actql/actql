///|
test "safe scalar constructors preserve admitted invariants" {
  assert_true(null_value() is Null)
  assert_true(boolean_value(true) is Boolean(true))
  assert_true(number_value(1.5) is Some(Number(1.5)))
  assert_true(number_value(0.0) is Some(Number(0.0)))
  assert_true(number_value(-0.0) is None)
  assert_true(number_value(0.0 / 0.0) is None)
  assert_true(number_value(1.0 / 0.0) is None)
  assert_true(text_value("é", 2) is Some(Text("é")))
  assert_true(text_value("é", 1) is None)
  assert_true(text_value("e\u{0301}", 3) is None)
}

///|
test "closed object construction detaches sorts and rejects invalid names" {
  let source = [
    ("z", number_value(2.0).unwrap()),
    ("__proto__", null_value()),
    ("a", boolean_value(true)),
  ]
  guard object_value(source) is Some(Object(fields)) else { fail("object") }
  source.clear()
  assert_eq(element_count(fields), 3)
  assert_eq(element_at(fields, 0).map(entry => entry.0), Some("__proto__"))
  assert_eq(element_at(fields, 1).map(entry => entry.0), Some("a"))
  assert_eq(element_at(fields, 2).map(entry => entry.0), Some("z"))
  assert_true(
    object_value([("a", null_value()), ("a", boolean_value(false))]) is None,
  )
  assert_true(object_value([("e\u{0301}", null_value())]) is None)
}

///|
test "owned array builder closes exact backing without reopening" {
  assert_true(prepare_array_value(-1) is None)
  let builder = prepare_array_value(2).unwrap()
  assert_true(append_array_item(builder, number_value(1.0).unwrap()))
  assert_true(append_array_item(builder, boolean_value(true)))
  assert_false(append_array_item(builder, null_value()))
  guard finish_array_value(builder) is Some(Array(items)) else { fail("array") }
  assert_eq(element_count(items), 2)
  assert_true(element_at(items, 0) is Some(Number(1.0)))
  assert_true(element_at(items, 1) is Some(Boolean(true)))
  assert_false(append_array_item(builder, null_value()))
  assert_true(finish_array_value(builder) is None)

  let incomplete = prepare_array_value(1).unwrap()
  assert_true(finish_array_value(incomplete) is None)
}

///|
test "bounded array and canonical object builders seal owned backing" {
  let array = prepare_array_value(3).unwrap()
  assert_true(append_array_item(array, number_value(1.0).unwrap()))
  guard finish_bounded_array_value(array) is Some(Array(items)) else {
    fail("bounded array")
  }
  assert_eq(element_count(items), 1)
  assert_false(append_array_item(array, number_value(2.0).unwrap()))

  let object = prepare_object_value(2).unwrap()
  assert_true(append_object_field(object, "a", boolean_value(true)))
  assert_true(append_object_field(object, "z", null_value()))
  guard finish_object_value(object) is Some(Object(fields)) else {
    fail("canonical object")
  }
  assert_eq(element_at(fields, 0).map(entry => entry.0), Some("a"))
  assert_eq(element_at(fields, 1).map(entry => entry.0), Some("z"))

  let invalid = prepare_object_value(2).unwrap()
  assert_true(append_object_field(invalid, "z", null_value()))
  assert_false(append_object_field(invalid, "a", null_value()))
  assert_true(finish_object_value(invalid) is None)
}
