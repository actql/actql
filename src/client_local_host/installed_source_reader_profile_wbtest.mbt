///|
test "standard Source profile uses original codec policies and distinct metadata response count" {
  assert_eq(installed_json_source_reader_profile(3, 20).unwrap(), [
    1000000, 103000000, 100000, 64, 100, 100, 103, 100, 4000000, 1000000, 9180448,
    10000, 1000000, 10000000, 100000, 100, 100, 10000, 10000, 1024, 10000000, 100000,
    65536,
  ])
  let without = installed_json_source_reader_profile(0, 20).unwrap()
  let selected = installed_json_source_reader_profile(3, 20).unwrap()
  assert_eq(selected[6] - without[6], 3)
  assert_eq(selected[1] - without[1], 3000000)
  assert_eq(selected[4], without[4])
  assert_eq(selected[5], without[5])
  assert_eq(
    installed_json_source_reader_profile(3, 21).unwrap()[10] - selected[10],
    1,
  )
  let provider = installed_json_source_reader_capacity(
    selected[:16].to_owned(),
    3,
    selected[22],
  ).unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(provider) > 0L)
  assert_true(
    @execution.execution_capacity_execution_bytes(provider) >
    @execution.execution_capacity_retained_bytes(provider),
  )
}

///|
test "standard Source profile refuses invalid counts and overflow without clipping" {
  assert_true(installed_json_source_reader_profile(-1, 20) is None)
  assert_true(installed_json_source_reader_profile(3, -1) is None)
  assert_true(installed_json_source_reader_profile(10000, 20) is None)
  assert_true(installed_json_source_reader_profile(2147483647, 20) is None)
  assert_true(installed_json_source_reader_profile(3, 2147483647) is None)
  assert_true(installed_json_source_reader_profile(3000, 20) is None)
}
