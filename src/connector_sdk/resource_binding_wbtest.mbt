///|
test "multiple resource bindings share an implementation without sharing identity" {
  let registry = prepare_capability_registry(
    [{ name: "compute", acquisition: false, fixed_compute: true, }],
    1,
    100,
  ).unwrap()
  let registration = capability_registration_at(registry, 0).unwrap()
  let first = prepare_resource_binding(registry, registration).unwrap()
  let second = prepare_resource_binding(registry, registration).unwrap()
  assert_false(physical_equal(first, second))
  assert_true(
    physical_equal(resource_binding_registration(first), registration),
  )
  assert_true(
    physical_equal(resource_binding_registration(second), registration),
  )
  let other = prepare_capability_registry(
    [{ name: "compute", acquisition: false, fixed_compute: true, }],
    1,
    100,
  ).unwrap()
  assert_true(
    prepare_resource_binding(other, registration) is Err(ForeignRegistration(0)),
  )
  close_capability_registry(registry)
  assert_true(
    prepare_resource_binding(registry, registration) is Err(RegistryClosed),
  )
  // Registry shutdown does not rewrite the identities retained for cleanup.
  assert_true(
    physical_equal(resource_binding_registration(first), registration),
  )
}
