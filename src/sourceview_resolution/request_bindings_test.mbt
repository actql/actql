///|
fn check_binding_requirements(
  requirements : RequestBindings,
  fields : Int,
  pending : Int,
  field_at : (Int) -> ParameterizedRequestField?,
) -> Unit raise {
  assert_eq(request_bindings_count(requirements), pending)
  assert_eq(request_bindings_work(requirements), fields + 1)
  let mut occurrence = 0
  for i in 0..<fields {
    let field = field_at(i).unwrap()
    if field.value is UnboundHostBinding(declaration) {
      assert_eq(request_binding_index(requirements, occurrence), Some(i))
      let retained = request_binding_at(requirements, occurrence).unwrap()
      assert_true(physical_equal(retained.field, field.field))
      assert_true(
        retained.value is UnboundHostBinding(d) &&
        physical_equal(d, declaration),
      )
      occurrence += 1
    }
  }
  assert_eq(occurrence, pending)
  for i in [-1, pending, 2147483647] {
    assert_true(request_binding_index(requirements, i) is None)
    assert_true(request_binding_at(requirements, i) is None)
  }
}
