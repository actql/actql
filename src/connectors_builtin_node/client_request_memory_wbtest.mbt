///|
test "Node memory bridge preserves omitted limits and projects only a complete Core selected pair" {
  let policy = client_local_resource_policy_original()
  let default = client_local_preparation_resource_limits(policy, None, None)
  assert_eq(default.length(), 6)
  assert_eq(default[4], 536870912L)
  assert_eq(default[5], 536870912L)
  let selected = client_local_preparation_resource_limits(
    policy,
    Some(268435456L),
    Some(1073741824L),
  )
  assert_eq(selected, [
    default[0],
    default[1],
    default[2],
    default[3],
    268435456L,
    1073741824L,
  ])
  assert_eq(
    client_local_preparation_resource_limits(policy, None, None),
    default,
  )
  assert_true(
    client_local_preparation_resource_limits(policy, Some(268435456L), None).is_empty(),
  )
  assert_true(
    client_local_preparation_resource_limits(
      policy,
      Some(0L),
      Some(1073741824L),
    ).is_empty(),
  )
}
