///|
// Explicit constructor DATA only. These tests issue no Request, grant or Run.
fn confirmation_recipe_profile(
  count : Int,
) -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
] {
  Array::make(
    count,
    (
      @execution.execution_capacity(16L, 32L).unwrap(),
      None,
      Some({ max_input_bytes: 128, max_nodes: 8, max_depth: 4, }),
    ),
  )
}

///|
fn confirmation_recipe_capacities(
  count : Int,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  installed_standard_create_request_recipe_capacities(
    Some(confirmation_recipe_profile(count)),
    4096,
    128,
    16,
    1024,
    32,
    8,
    2048,
    4096,
    2048,
    4096,
    false,
    64,
    7,
    256,
    4096,
    128,
    16,
    0L,
  )
}

///|
test "confirmed CREATE recipe forwards all seven native roles and keeps distinct physical and finalization quantities" {
  let old = confirmation_recipe_capacities(4).unwrap()
  let confirmed = confirmation_recipe_capacities(7).unwrap()
  assert_eq(old.length(), 6)
  assert_eq(confirmed.length(), 8)
  for index in [0, 1, 2, 3, 5] {
    assert_eq(
      @execution.execution_capacity_retained_bytes(confirmed[index]),
      @execution.execution_capacity_retained_bytes(old[index]),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(confirmed[index]),
      @execution.execution_capacity_execution_bytes(old[index]),
    )
  }
  assert_true(
    @execution.execution_capacity_retained_bytes(confirmed[4]) >
    @execution.execution_capacity_retained_bytes(old[4]),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(confirmed[6]) >
    @execution.execution_capacity_retained_bytes(confirmed[2]),
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(confirmed[7]),
    @execution.execution_capacity_retained_bytes(confirmed[5]),
  )
}

///|
test "confirmed CREATE recipe keeps absent and incomplete native inventories refused" {
  assert_true(
    installed_standard_create_constructor_capacities(None) is Err(Unsupported),
  )
  for count in [0, 1, 3, 5, 6, 8] {
    assert_true(confirmation_recipe_capacities(count) is Err(Unsupported))
  }
}
