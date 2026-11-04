///|
fn physical_write_recipe_fixture(
  physical : @execution.ExecutionCapacity,
  request? : Int = 100000,
  response? : Int = 2,
  control? : Int = 0,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  installed_physical_write_recipe_capacities(
    100000, 10000, 16, 1000000, 100000, 64,
    request, 100000, response, 1000000, 512, 16, physical,
    control_wire_bytes=if control == 0 { None } else { Some(control) },
  )
}

///|
test "physical writer recipe retains original constructor and unchanged capture/control siblings" {
  let first = @execution.execution_capacity(1234L, 5678L).unwrap()
  let second = @execution.execution_capacity(1235L, 5680L).unwrap()
  let a = physical_write_recipe_fixture(first).unwrap()
  let b = physical_write_recipe_fixture(second).unwrap()
  assert_eq(a.length(), 6)
  assert_eq(@execution.execution_capacity_retained_bytes(a[3]), 1234L)
  assert_eq(@execution.execution_capacity_execution_bytes(a[3]), 5678L)
  assert_eq(@execution.execution_capacity_retained_bytes(b[3]), 1235L)
  assert_eq(@execution.execution_capacity_execution_bytes(b[3]), 5680L)
  for index in [0, 1, 2, 4, 5] {
    assert_eq(@execution.execution_capacity_retained_bytes(a[index]), @execution.execution_capacity_retained_bytes(b[index]))
    assert_eq(@execution.execution_capacity_execution_bytes(a[index]), @execution.execution_capacity_execution_bytes(b[index]))
  }
  assert_true(@execution.execution_capacity_retained_bytes(a[4]) >= 2000000L)
}

///|
test "physical writer refuses invalid bounds and retains full failed request envelope" {
  let physical = @execution.execution_capacity(10L, 20L).unwrap()
  assert_true(physical_write_recipe_fixture(physical, request=0) is Err(Unsupported))
  assert_true(physical_write_recipe_fixture(physical, response=0) is Err(Unsupported))
  assert_true(physical_write_recipe_fixture(physical, control=-1) is Err(Unsupported))
  assert_true(physical_write_recipe_fixture(physical, control=1000001) is Err(Unsupported))
  let narrow = physical_write_recipe_fixture(physical, request=10).unwrap()
  let wide = physical_write_recipe_fixture(physical, request=100).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(narrow[2]) > 100000L)
  assert_true(@execution.execution_capacity_execution_bytes(wide[2]) > @execution.execution_capacity_execution_bytes(narrow[2]))
}
