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

///|
test "Common completed Unit profile preserves live Reader carriers and full initial quote" {
  let none = client_program_hubspot_effect_constructor_capacity(9, [], [], []).unwrap()
  let reader = @hubspot_catalog.effect_metadata_disposed_construction_capacity().unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(none),
    @execution.execution_capacity_retained_bytes(reader),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(none),
    @execution.execution_capacity_execution_bytes(reader),
  )
  assert_true(@execution.execution_capacity_retained_bytes(none) > 0L)
  for (input, output, counts) in [([1], [], []), ([], [1], []), ([], [], [1])] {
    assert_true(
      client_program_hubspot_effect_constructor_capacity(
        9, input, output, counts,
      )
      is None,
    )
  }
  let original = client_program_installed_effect_operation_extent_from_capacity(
    "schema",
    @execution.execution_capacity(20L, 80L).unwrap(),
    7L,
    true,
  ).unwrap()
  let bound = client_program_installed_effect_operation_discarded_projection_extent_prepare(
    original,
    @execution.execution_capacity(7L, 15L).unwrap(),
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(
      @client_local_host.installed_effect_operation_extent_capacity(bound),
    ),
    20L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(
      @client_local_host.installed_effect_operation_extent_capacity(bound),
    ),
    80L,
  )
  assert_true(
    client_program_installed_effect_operation_discarded_projection_extent_prepare(
      original,
      @execution.execution_capacity(21L, 80L).unwrap(),
    )
    is Err(Unsupported),
  )
}
