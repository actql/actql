///|
test "Common recheck selector preserves its native Map quote and rejects other geometry" {
  let expected = @hubspot_catalog.effect_catalog_recheck_construction_capacity(
    256,
  ).unwrap()
  let actual = client_program_hubspot_effect_constructor_capacity(
    8,
    [256],
    [],
    [],
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(actual),
    @execution.execution_capacity_retained_bytes(expected),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(actual),
    @execution.execution_capacity_execution_bytes(expected),
  )
  assert_true(
    client_program_hubspot_effect_constructor_capacity(8, [0], [], []) is None,
  )
  assert_true(
    client_program_hubspot_effect_constructor_capacity(8, [], [], []) is None,
  )
  assert_true(
    client_program_hubspot_effect_constructor_capacity(8, [256], [1], [])
    is None,
  )
  assert_true(
    client_program_hubspot_effect_constructor_capacity(8, [256], [], [1])
    is None,
  )
}
