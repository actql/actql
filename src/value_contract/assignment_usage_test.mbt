///|
test "assignment usage counts compared pairs on success and incompatibility" {
  let number = primitive(NumberType, nullable=false)
  let text = primitive(StringType, nullable=false)
  assert_eq(assignable_usage(number, number, 1), (true, 1))
  assert_eq(assignable_usage(number, text, 1), (false, 1))
  let a = array_contract(number, nullable=false).unwrap()
  let b = array_contract(text, nullable=false).unwrap()
  assert_eq(assignable_usage(a, a, 2), (true, 2))
  assert_eq(assignable_usage(a, b, 2), (false, 2))
  let failed = try {
    ignore(assignable_usage(a, a, 1))
    false
  } catch {
    RelationLimit => true
    _ => false
  }
  assert_true(failed)
}
