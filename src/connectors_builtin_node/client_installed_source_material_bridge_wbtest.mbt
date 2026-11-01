///|
test "retained Source optional constructor quantity remains typed and absent quantity refuses" {
  let original = @execution.execution_capacity(5L, 7L).unwrap()
  let output = client_program_installed_source_retained_construction_capacity(
      Some(original),
    )
    .unwrap()
    .unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(output), 5L)
  assert_eq(@execution.execution_capacity_execution_bytes(output), 5L)
  assert_true(
    client_program_installed_source_retained_construction_capacity(None)
    is Err(@resources.InvalidExtent),
  )
}
